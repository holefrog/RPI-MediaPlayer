#!/usr/bin/env python
# resources/oled/query.py (重构版 - 修复审核建议 #6)
import base64
import getpass
import json
import logging
import os
import re
import socket
import subprocess
import time

import requests

logger = logging.getLogger(__name__)


BT_VOLUME_MAX = 127  # Bluetooth A2DP volume range: 0-127

# ============================================
# 全局状态
# ============================================
_AIRPLAY_PIPE = None
_airplay_state = {"artist": "", "title": "", "volume": -1, "buffer": ""}
_pipe_fd = None
_bt_player_path = None
_last_bt_volume = -1


# ============================================
# AirPlay 管道初始化（修复审核建议 #6 - 强制初始化）
# ============================================
def init_airplay_pipe(pipe_path):
    """
    初始化 AirPlay metadata 管道路径（必须在使用前调用）

    Args:
        pipe_path: 从配置文件读取的管道路径
        
    Raises:
        RuntimeError: 如果管道路径无效
    """
    global _AIRPLAY_PIPE
    
    if not pipe_path:
        raise RuntimeError("AirPlay 管道路径不能为空")
    
    _AIRPLAY_PIPE = pipe_path
    logger.info(f"AirPlay 管道路径已设置: {_AIRPLAY_PIPE}")


# ============================================
# 基础网络/LMS
# ============================================
def check_network(host, port):
    try:
        socket.create_connection((host, port), timeout=5)
        return True
    except socket.error as e:
        logger.error(f"Network check failed: {host}:{port}, error={e}")
        return False


def get_player_status(cmd, host_ip, host_port, player_id, retries=3, delay=2):
    url = f'http://{host_ip}:{host_port}/jsonrpc.js'
    headers = {'Content-Type': 'application/json'}
    data = {"id": 1, "method": "slim.request", "params": [player_id, cmd]}

    for attempt in range(retries):
        try:
            response = requests.post(url, headers=headers, json=data, timeout=1)
            response.raise_for_status()
            return None, response.json()
        except Exception as e:
            if attempt < retries - 1:
                time.sleep(0.2)
            else:
                return f"Error: {e}", None


def extract_result_field(result, field, default="N/A"):
    if not isinstance(result, dict):
        return default
    result_dict = result.get('result', {})
    if not isinstance(result_dict, dict):
        return default
    return result_dict.get(field, default)


# ============================================
# PipeWire 状态
# ============================================
def setup_pactl_env():
    user = getpass.getuser()
    uid = os.getuid()
    env = os.environ.copy()
    if "XDG_RUNTIME_DIR" not in env:
        env["XDG_RUNTIME_DIR"] = f"/run/user/{uid}"
    env["LC_ALL"] = "C"
    return env


def get_high_priority_source(pactl_env):
    """
    检查 PipeWire 活跃源
    Returns: (source_type, status)
             status: "playing" | "paused"
    """
    try:
        env = pactl_env.copy()
        env["LC_ALL"] = "C"

        result = subprocess.run(
            ['pactl', 'list', 'sink-inputs'],
            capture_output=True,
            text=True,
            check=True,
            env=env,
            timeout=1
        )
        output = result.stdout.lower()
        sink_inputs = output.split('sink input #')

        # 第一轮：查找正在播放的
        for block in sink_inputs:
            if not block.strip():
                continue
            if "corked: no" in block:
                if "shairport" in block:
                    return "airplay", "playing"
                if "bluez" in block:
                    return "bluetooth", "playing"

        # 第二轮：查找已暂停的
        for block in sink_inputs:
            if not block.strip():
                continue
            if "corked: yes" in block:
                if "shairport" in block:
                    return "airplay", "paused"
                if "bluez" in block:
                    return "bluetooth", "paused"

    except Exception as e:
        logger.warning(f"Pactl check failed: {e}")

    return None, "stopped"


def check_bluetooth_connected(pactl_env):
    try:
        result = subprocess.run(
            ["pactl", "list", "sinks"],
            capture_output=True,
            text=True,
            check=True,
            env=pactl_env,
            timeout=1,
        )
        return "bluez_sink" in result.stdout.lower()
    except Exception:
        return False


def get_system_volume(pactl_env):
    try:
        result = subprocess.run(
            ['pactl', 'get-sink-volume', '@DEFAULT_SINK@'],
            capture_output=True,
            text=True,
            check=True,
            env=pactl_env,
            timeout=1
        )
        m = re.search(r'(\d+)%', result.stdout)
        if m:
            return max(0, min(100, int(m.group(1))))
    except Exception:
        pass
    return 0


# ============================================
# AirPlay 元数据（修复审核建议 #6 - 强制检查）
# ============================================
def update_airplay_metadata():
    """
    读取 AirPlay metadata 管道

    Returns:
        tuple: (artist, title, volume)
        
    Raises:
        RuntimeError: 如果管道路径未初始化
    """
    global _pipe_fd, _airplay_state, _AIRPLAY_PIPE

    # 修复审核建议 #6：强制中断而非仅记录错误
    if _AIRPLAY_PIPE is None:
        raise RuntimeError(
            "AirPlay 管道路径未初始化！必须先调用 init_airplay_pipe()\n"
            "请检查 main.py 是否正确调用了初始化函数。"
        )

    if _pipe_fd is None:
        if os.path.exists(_AIRPLAY_PIPE):
            try:
                _pipe_fd = os.open(_AIRPLAY_PIPE, os.O_RDONLY | os.O_NONBLOCK)
                logger.info(f"Pipe opened: {_AIRPLAY_PIPE}")
            except Exception as e:
                logger.error(f"Failed to open pipe: {e}")
        return _airplay_state["artist"], _airplay_state["title"], _airplay_state["volume"]

    try:
        while True:
            chunk = os.read(_pipe_fd, 8192)
            if not chunk:
                break
            _airplay_state["buffer"] += chunk.decode('utf-8', errors='ignore')
    except BlockingIOError:
        pass
    except Exception:
        try:
            os.close(_pipe_fd)
        except Exception:
            pass
        _pipe_fd = None
        return _airplay_state["artist"], _airplay_state["title"], _airplay_state["volume"]

    while '<item>' in _airplay_state["buffer"] and '</item>' in _airplay_state["buffer"]:
        start = _airplay_state["buffer"].find('<item>')
        end = _airplay_state["buffer"].find('</item>') + 7
        item_block = _airplay_state["buffer"][start:end]
        _airplay_state["buffer"] = _airplay_state["buffer"][end:]

        try:
            code_match = re.search(r'<code>([0-9a-f]+)</code>', item_block)
            if not code_match:
                continue
            code = code_match.group(1)
            data_match = re.search(
                r'<data encoding="base64">\s*([A-Za-z0-9+/=\s]+)\s*</data>',
                item_block,
                re.DOTALL
            )
            if not data_match:
                continue
            base64_str = re.sub(r'\s+', '', data_match.group(1))

            if code == '6d696e6d':  # minm (Title)
                _airplay_state["title"] = base64.b64decode(base64_str).decode('utf-8', errors='ignore')
            elif code == '61736172':  # asar (Artist)
                _airplay_state["artist"] = base64.b64decode(base64_str).decode('utf-8', errors='ignore')
            elif code == '70766f6c':  # pvol (Volume)
                try:
                    vol_str = base64.b64decode(base64_str).decode('utf-8', errors='ignore')
                    parts = vol_str.split(',')
                    if len(parts) >= 1:
                        curr_db = float(parts[0])
                        min_db = -30.0
                        max_db = 0.0
                        if len(parts) >= 4:
                            max_db = float(parts[3])
                        
                        new_vol = 0
                        if curr_db < -100:
                            new_vol = 0
                        elif curr_db >= max_db:
                            new_vol = 100
                        elif curr_db <= min_db:
                            new_vol = 0
                        else:
                            pct = (curr_db - min_db) / (max_db - min_db) * 100
                            new_vol = int(max(0, min(100, pct)))
                        _airplay_state["volume"] = new_vol
                except Exception:
                    pass
        except Exception:
            pass

    return _airplay_state["artist"], _airplay_state["title"], _airplay_state["volume"]


# ============================================
# Bluetooth
# ============================================
def get_bluetooth_volume_dbus():
    global _last_bt_volume
    try:
        cmd = [
            "dbus-send",
            "--system",
            "--dest=org.bluez",
            "--print-reply",
            "/",
            "org.freedesktop.DBus.ObjectManager.GetManagedObjects"
        ]
        output = subprocess.check_output(cmd, timeout=1).decode()
        paths = re.findall(r'object path "(/org/bluez/hci[0-9]*/dev_[^"]+)"', output)
        
        for path in paths:
            if "/fd" not in path:
                continue
            try:
                cmd_vol = [
                    "dbus-send",
                    "--system",
                    "--print-reply",
                    "--dest=org.bluez",
                    path,
                    "org.freedesktop.DBus.Properties.Get",
                    "string:org.bluez.MediaTransport1",
                    "string:Volume",
                ]
                res = subprocess.check_output(
                    cmd_vol,
                    stderr=subprocess.DEVNULL,
                    timeout=0.5
                ).decode()
                m = re.search(r'uint16\s+(\d+)', res)
                if m:
                    return int((int(m.group(1)) / BT_VOLUME_MAX) * 100)
            except Exception:
                continue
    except Exception:
        pass
    return -1


def _extract_variant_string(lines, start_index):
    for j in range(start_index + 1, min(start_index + 5, len(lines))):
        sub = lines[j].strip()
        if sub.startswith('variant') and 'string "' in sub:
            parts = sub.split('"')
            if len(parts) >= 3:
                return parts[1]
    return ""


def get_bluetooth_metadata():
    """获取蓝牙信息，返回: (Artist, Title, Status)"""
    global _bt_player_path

    if not _bt_player_path:
        try:
            cmd = [
                "dbus-send",
                "--system",
                "--dest=org.bluez",
                "--print-reply",
                "/",
                "org.freedesktop.DBus.ObjectManager.GetManagedObjects"
            ]
            output = subprocess.check_output(cmd, timeout=1).decode()
            m = re.search(
                r'object path "(/org/bluez/hci[0-9]*/dev_[^"]+/player\d+)"',
                output,
                re.IGNORECASE
            )
            if m:
                _bt_player_path = m.group(1)
            else:
                return "", "", "unknown"
        except Exception:
            return "", "", "unknown"

    try:
        # 获取 Track
        cmd = [
            "dbus-send",
            "--system",
            "--print-reply",
            "--dest=org.bluez",
            _bt_player_path,
            "org.freedesktop.DBus.Properties.Get",
            "string:org.bluez.MediaPlayer1",
            "string:Track",
        ]

        output = subprocess.check_output(cmd, timeout=1).decode()
        artist = ""
        title = ""
        lines = output.split('\n')
        for i, line in enumerate(lines):
            line = line.strip()
            if 'string "Title"' in line:
                title = _extract_variant_string(lines, i)
            elif 'string "Artist"' in line:
                artist = _extract_variant_string(lines, i)

        # 获取 Status
        cmd_status = [
            "dbus-send",
            "--system",
            "--print-reply",
            "--dest=org.bluez",
            _bt_player_path,
            "org.freedesktop.DBus.Properties.Get",
            "string:org.bluez.MediaPlayer1",
            "string:Status",
        ]
        res_status = subprocess.check_output(
            cmd_status,
            stderr=subprocess.DEVNULL
        ).decode()
        
        status = "unknown"
        if 'string "playing"' in res_status.lower():
            status = "playing"
        elif 'string "paused"' in res_status.lower():
            status = "paused"
        elif 'string "stopped"' in res_status.lower():
            status = "stopped"

        return artist, title, status

    except Exception:
        _bt_player_path = None
        return "", "", "unknown"
