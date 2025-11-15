import time
import os
import subprocess
import getpass
from query import get_player_status, extract_result_field
from display import display_text, set_brightness, turn_off_display, turn_on_display
from config import load_config  # 导入配置文件加载函数

# 屏幕管理常量
DIM_SCREEN_TIMEOUT = 5
TURN_OFF_SCREEN_TIMEOUT = 900
DEFAULT_BRIGHTNESS = 255
DIM_BRIGHTNESS = 8

# 屏幕状态变量
is_off = False
is_dimmed = False
start_time = time.time()
last_content_state = None
last_state_key = None

# 加载配置
host_ip, host_port, player_id = load_config()
print(f"INFO: 配置加载: host_ip={host_ip}, host_port={host_port}, player_id={player_id}")

# 检查 systemd 用户服务
def is_user_service_active(service_name, user=None):
    if user is None:
        user = getpass.getuser()
    try:
        uid = int(subprocess.check_output(["id", "-u", user]).decode().strip())
    except Exception as e:
        print(f"ERROR: 获取用户 {user} 的 UID 失败: {e}")
        return False

    xdg_runtime_dir = f"/run/user/{uid}"
    try:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", "--quiet", service_name],
            env={"XDG_RUNTIME_DIR": xdg_runtime_dir, **dict(os.environ)},
        )
        print(f"DEBUG: 检查服务 {service_name} 状态: {'active' if result.returncode == 0 else 'inactive'}")
        return result.returncode == 0
    except Exception as e:
        print(f"ERROR: 检查服务 {service_name} 失败: {e}")
        return False

def wait_for_service(service_name, timeout=30):
    start_time = time.time()
    while not is_user_service_active(service_name):
        if time.time() - start_time > timeout:
            print(f"ERROR: 服务 {service_name} 启动超时 ({timeout}秒)")
            return False
        time.sleep(1)
    print(f"DEBUG: 服务 {service_name} 已启动")
    return True

# 启动检查
print("INFO: 系统启动")
display_text("Booting", "Wait", large_font=True)
time.sleep(5)

display_text("Checking", "Audio", large_font=True)
if not wait_for_service("pipewire", timeout=10):
    print("ERROR: PipeWire 服务未启动！")
else:
    display_text("Audio", "Done", large_font=True)
    time.sleep(1)

display_text("Checking", "Squeeze", large_font=True)
if not wait_for_service("squeezelite", timeout=10):
    print("ERROR: Squeezelite 服务未启动！")
else:
    display_text("squeezelite", "Done", large_font=True)
    time.sleep(1)

display_text("System", "Ready", large_font=True)
time.sleep(1)

# 主循环
print("INFO: 主循环开始")
while True:
    try:
        current_date = time.strftime("%Y-%m-%d", time.localtime())
        current_time = time.strftime("%H:%M:%S", time.localtime())
        print(f"DEBUG: 当前时间: date={current_date}, time={current_time}")

        # 获取播放器状态，传递配置参数
        error, result = get_player_status(["power", "?"], host_ip, host_port, player_id)
        if error:
            print(f"ERROR: 获取播放器状态失败: {error}")
            display_text("Error", error, large_font=False)
            time.sleep(5)
            continue

        power = extract_result_field(result, "_power", default=0)
        print(f"DEBUG: 播放器电源状态: power={power}")

        state_key = None
        content_state = None

        if power == 0:
            state_key = "power_off"
            content_state = ("power_off", current_date, current_time)
            print(f"DEBUG: 状态: power_off, 显示内容: {content_state}")
            display_text(current_date, current_time, large_font=True, scroll_speed=0, is_time_update=True)
            last_content_state = content_state

        else:
            error, result = get_player_status(["mode", "?"], host_ip, host_port, player_id)
            if error:
                print(f"ERROR: 获取播放模式失败: {error}")
                display_text("Error", "Get mode", large_font=True)
                time.sleep(5)
                continue
            playback_mode = extract_result_field(result, "_mode", default="stop")
            print(f"DEBUG: 播放模式: {playback_mode}")

            if playback_mode == "stop":
                state_key = "stop"
                content_state = ("stop", current_time)
                print(f"DEBUG: 状态: stop, 显示内容: {content_state}")
                display_text("Stopped", current_time, large_font=True, scroll_speed=0, is_time_update=True)
                last_content_state = content_state

            elif playback_mode == "pause":
                state_key = "pause"
                content_state = ("pause", current_time)
                print(f"DEBUG: 状态: pause, 显示内容: {content_state}")
                display_text("Paused", current_time, large_font=True, scroll_speed=0, is_time_update=True)
                last_content_state = content_state

            elif playback_mode == "play":
                state_key = "play"
                error, result = get_player_status(["current_title", "?"], host_ip, host_port, player_id)
                if error:
                    print(f"ERROR: 获取歌曲标题失败: {error}")
                    display_text("Error", "Get title", large_font=True)
                    time.sleep(5)
                    continue
                track_title = extract_result_field(result, "_current_title", default="")
                
                error, result = get_player_status(["artist", "?"], host_ip, host_port, player_id)
                if error:
                    print(f"ERROR: 获取艺术家失败: {error}")
                    display_text("Error", "Get artist", large_font=True)
                    time.sleep(5)
                    continue
                artist = extract_result_field(result, "_artist", default="")
                
                content_state = ("play", artist, track_title)
                print(f"DEBUG: 状态: play, 显示内容: artist={artist}, title={track_title}")
                if content_state != last_content_state:
                    display_text(artist, track_title, large_font=True, scroll_speed=0.00625, is_time_update=False)
                    last_content_state = content_state

            else:
                state_key = "unknown"
                content_state = ("unknown", current_date, current_time)
                print(f"DEBUG: 状态: unknown, 显示内容: {content_state}")
                display_text(current_date, current_time, large_font=True, scroll_speed=0, is_time_update=True)
                last_content_state = content_state

        # 屏幕亮度管理
        if state_key != last_state_key:
            last_state_key = state_key
            start_time = time.time()
            is_dimmed = False
            if is_off:
                try:
                    turn_on_display()
                    is_off = False
                    print("INFO: 屏幕打开")
                except Exception as e:
                    print(f"ERROR: 打开屏幕失败: {e}")
            else:
                try:
                    set_brightness(DEFAULT_BRIGHTNESS)
                    print(f"INFO: 恢复亮度到 {DEFAULT_BRIGHTNESS}")
                except Exception as e:
                    print(f"ERROR: 设置亮度失败: {e}")

        elapsed = time.time() - start_time
        if not is_dimmed and elapsed > DIM_SCREEN_TIMEOUT:
            try:
                set_brightness(DIM_BRIGHTNESS)
                is_dimmed = True
                print(f"INFO: 屏幕调暗到 {DIM_BRIGHTNESS}")
            except Exception as e:
                print(f"ERROR: 调暗屏幕失败: {e}")

        if not is_off and elapsed > TURN_OFF_SCREEN_TIMEOUT:
            try:
                turn_off_display()
                is_off = True
                print("INFO: 屏幕关闭")
            except Exception as e:
                print(f"ERROR: 关闭屏幕失败: {e}")

        time.sleep(1)

    except Exception as e:
        print(f"ERROR: 主循环异常: {e}")
        time.sleep(5)
