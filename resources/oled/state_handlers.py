#!/usr/bin/env python
# resources/oled/state_handlers.py

import time
from query import (
    update_airplay_metadata, get_system_volume,
    get_bluetooth_metadata, get_bluetooth_volume_dbus,
    get_player_status, extract_result_field, check_bluetooth_connected
)

class PlayerState:
    """用于在函数间传递播放器状态的简单容器"""
    def __init__(self):
        self.key = None            # 状态唯一标识 (用于屏保判断)
        self.signature = None      # 内容唯一标识 (用于刷新判断)
        self.top_text = ""
        self.bottom_text = ""
        self.volume = -1           # -1 表示不显示音量
        self.is_paused = False
        self.active_player_type = None # 用于记录当前占用的播放器类型
        
        # 显示参数默认值
        self.large_font = True
        self.scroll_speed = 0.0
        self.align_mode = "center" # "center" 或 "left"
        self.is_clock = False

def handle_airplay_state(pactl_env, source_status, last_known_volume, cfg_display):
    """处理 AirPlay 状态逻辑"""
    state = PlayerState()
    state.active_player_type = "airplay"
    state.key = "airplay"
    
    # 获取 AirPlay 元数据
    artist, title, ap_vol = update_airplay_metadata()
    
    # 判断是否暂停
    if source_status == "paused":
        state.is_paused = True
        state.volume = last_known_volume
        state.top_text = "AP: 已暂停"
        state.bottom_text = title if title else "AirPlay"
        state.scroll_speed = cfg_display["scroll_speed_static"]
    else:
        # 优先使用 AirPlay 自身音量，如果没有则回退到系统音量
        if ap_vol >= 0: 
            state.volume = ap_vol
        else: 
            state.volume = get_system_volume(pactl_env)
            
        state.top_text = f"AP: {artist if artist else '未知'}"
        state.bottom_text = title if title else "AirPlay"
        state.scroll_speed = cfg_display["scroll_speed_playing"]

    # 生成内容签名
    state.signature = f"ap_{artist}_{title}_{source_status}"
    state.align_mode = "left"
    state.large_font = True
    return state

def handle_bluetooth_state(pactl_env, source_status, last_known_volume, cfg_display):
    """处理 Bluetooth 状态逻辑"""
    state = PlayerState()
    state.active_player_type = "bluetooth"
    state.key = "bluetooth"

    # 获取蓝牙元数据
    artist, title, bt_status_meta = get_bluetooth_metadata()
    
    # 综合判定暂停状态 (PipeWire 状态 或 元数据状态)
    is_paused = (source_status == "paused") or (bt_status_meta == "paused")
    state.is_paused = is_paused

    display_title = title if title else "Bluetooth"
    display_artist = artist if artist else "未知"

    if is_paused:
        state.volume = last_known_volume
        state.top_text = "BT: 已暂停"
        state.bottom_text = display_title
        state.scroll_speed = cfg_display["scroll_speed_static"]
    else:
        # 获取蓝牙音量
        bt_vol = get_bluetooth_volume_dbus()
        if bt_vol >= 0:
            state.volume = bt_vol
        else:
            state.volume = get_system_volume(pactl_env)
            
        state.top_text = f"BT: {display_artist}"
        state.bottom_text = display_title
        state.scroll_speed = cfg_display["scroll_speed_playing"]

    state.signature = f"bt_{artist}_{title}_{is_paused}"
    state.align_mode = "left"
    state.large_font = True
    return state

def handle_lms_or_idle_state(pactl_env, lms_config, current_active_type, last_known_volume, cfg_display):
    """处理 LMS (Squeezelite) 或 空闲/时钟 状态逻辑"""
    state = PlayerState()
    
    # 1. 特殊处理：蓝牙刚刚暂停时的反馈 (防止状态在蓝牙暂停和LMS之间快速跳变)
    # 如果当前主要类型是蓝牙，且检测到蓝牙暂停，保持蓝牙显示
    bt_artist, bt_title, bt_status_check = get_bluetooth_metadata()
    if bt_status_check == "paused" and current_active_type == "bluetooth":
        state.active_player_type = "bluetooth"
        state.key = "bluetooth_paused_fb"
        state.is_paused = True
        state.volume = last_known_volume
        
        state.top_text = "BT: 已暂停"
        state.bottom_text = bt_title if bt_title else "Bluetooth"
        state.align_mode = "left"
        state.scroll_speed = cfg_display["scroll_speed_static"]
        state.signature = "bt_paused_fb"
        state.large_font = True
        return state

    # 2. 查询 LMS (Squeezelite) 状态
    # 注意：这里使用 lms_config 字典解包传参
    error, result = get_player_status(
        ["mode", "?"], 
        lms_config["host_ip"], lms_config["host_port"], lms_config["player_id"]
    )
    playback_mode = extract_result_field(result, "_mode", default="stop")

    # === 场景 C1: LMS 播放中 ===
    if playback_mode == "play":
        state.active_player_type = "squeezelite"
        state.key = "squeezelite"
        
        # 获取元数据
        _, res_t = get_player_status(["current_title", "?"], **lms_config)
        _, res_a = get_player_status(["artist", "?"], **lms_config)
        
        sq_title = extract_result_field(res_t, "_current_title", default="Squeezelite")
        sq_artist = extract_result_field(res_a, "_artist", default="未知")
        
        # 获取 LMS 音量
        _, vol_res = get_player_status(["mixer", "volume", "?"], **lms_config)
        lms_vol_raw = extract_result_field(vol_res, "_volume", default=None)
        try: 
            state.volume = int(float(lms_vol_raw))
        except: 
            state.volume = last_known_volume

        state.top_text = f"SQ: {sq_artist}"
        state.bottom_text = sq_title
        state.align_mode = "left"
        state.scroll_speed = cfg_display["scroll_speed_playing"]
        state.signature = f"sq_{sq_artist}_{sq_title}"
        state.large_font = True
        return state

    # === 场景 C2: LMS 暂停 ===
    elif playback_mode == "pause" and current_active_type == "squeezelite":
        state.active_player_type = "squeezelite"
        state.key = "squeeze_pause"
        state.is_paused = True
        state.volume = last_known_volume
        
        _, res_t = get_player_status(["current_title", "?"], **lms_config)
        sq_title = extract_result_field(res_t, "_current_title", default="Squeezelite")
        
        state.top_text = "SQ: 已暂停"
        state.bottom_text = sq_title
        state.align_mode = "left"
        state.scroll_speed = cfg_display["scroll_speed_static"]
        state.signature = "sq_pause"
        state.large_font = True
        return state

    # === 场景 C3: 纯空闲状态 (Idle) ===
    state.active_player_type = None # 重置，无活跃播放器
    
    if check_bluetooth_connected(pactl_env):
        # 蓝牙已连接但未播放
        state.key = "bt_connected"
        state.top_text = "Bluetooth"
        state.bottom_text = "已连接"
        state.scroll_speed = cfg_display["scroll_speed_static"]
        state.signature = "bt_conn"
        state.large_font = True
    else:
        # 时钟模式
        state.key = "idle"
        state.is_clock = True
        state.top_text = time.strftime("%Y-%m-%d", time.localtime())
        state.bottom_text = time.strftime("%H:%M:%S", time.localtime())
        state.scroll_speed = 0
        state.signature = "idle"
        state.large_font = True
        
    state.volume = -1 # 不显示音量
    return state
