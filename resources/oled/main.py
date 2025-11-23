#!/usr/bin/env python
# resources/oled/main.py (修复版 - 支持配置化日志级别)

import time
import sys 
import logging

from config import load_config
from display import init_display, display_text
from query import setup_pactl_env, get_high_priority_source, init_airplay_pipe
from screensaver import ScreenSaver

# 引入新的状态处理器
from state_handlers import (
    handle_airplay_state, 
    handle_bluetooth_state, 
    handle_lms_or_idle_state
)

# ============================================
# 初始化日志配置（临时使用 INFO 级别）
# ============================================
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(name)s] [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger("Main")

def main():
    try:
        # ============================================
        # 1. 加载配置
        # ============================================
        cfg = load_config()
        
        # 🆕 重新配置日志级别（使用配置文件中的设置）
        log_level = cfg["oled"]["log_level"]
        logging.getLogger().setLevel(log_level)
        
        logger.info(f"日志级别已设置为: {logging.getLevelName(log_level)}")
        
        # 将 LMS 参数打包成字典，方便后续传递
        lms_params = {
            "host_ip": cfg["lms"]["host_ip"],
            "host_port": cfg["lms"]["host_port"],
            "player_id": cfg["lms"]["player_id"]
        }
        
        # ============================================
        # 2. 初始化环境
        # ============================================
        display_ctx = init_display(
            port=cfg["oled"]["bus"],
            address=cfg["oled"]["address"],
            w=cfg["oled"]["width"],
            h=cfg["oled"]["height"],
            display_config=cfg["display"]
        )
        
        pactl_env = setup_pactl_env()
        init_airplay_pipe(cfg["airplay"]["metadata_pipe"])
        
        screen_saver = ScreenSaver(
            display_ctx,
            dim_timeout=cfg["screensaver"]["dim_timeout"],
            off_timeout=cfg["screensaver"]["off_timeout"]
        )
        
        logger.info("System Ready")
        
    except Exception as e:
        logger.error(f"Startup failed: {e}")
        sys.exit(1)

    # ============================================
    # 3. 主循环变量
    # ============================================
    last_state_key = None
    last_content_signature = None 
    last_display_args = None      
    
    last_known_volume = -1
    volume_popup_start = 0
    active_player_type = None # 记录当前是谁在占用 (airplay/bluetooth/squeezelite)

    # 显示启动画面
    display_text(display_ctx, "System", "Ready", large_font=True)
    time.sleep(1)

    while True:
        try:
            # 3.1 获取高优先级音源 (AirPlay / Bluetooth)
            hi_priority_source, source_status = get_high_priority_source(pactl_env)
            
            current_state = None

            # 3.2 根据源类型分发处理 (策略模式)
            if hi_priority_source == "airplay":
                current_state = handle_airplay_state(
                    pactl_env, source_status, last_known_volume, cfg["display"]
                )
            
            elif hi_priority_source == "bluetooth":
                current_state = handle_bluetooth_state(
                    pactl_env, source_status, last_known_volume, cfg["display"]
                )
            
            else:
                # Squeezelite 或 空闲
                current_state = handle_lms_or_idle_state(
                    pactl_env, lms_params, active_player_type, last_known_volume, cfg["display"]
                )

            # 更新全局状态记录
            active_player_type = current_state.active_player_type

            # 3.3 音量弹窗逻辑
            real_current_volume = current_state.volume
            show_volume = False
            
            # 如果不在暂停状态且有有效音量，则进行音量变化检测
            if not current_state.is_paused and real_current_volume >= 0:
                if real_current_volume != last_known_volume:
                    if last_known_volume != -1: # 忽略首次启动的跳变
                        volume_popup_start = time.time()
                    last_known_volume = real_current_volume
                
                # 检查弹窗是否超时
                if time.time() - volume_popup_start < cfg["volume"]["popup_duration"]:
                    show_volume = True
            
            # 决定最终传递给 display 的音量参数
            final_volume = real_current_volume if show_volume else None
            
            # 组装显示参数
            display_args = (
                current_state.top_text,
                current_state.bottom_text,
                current_state.large_font,
                current_state.scroll_speed,
                current_state.is_clock,
                final_volume,
                current_state.align_mode
            )

            # 3.4 屏保管理
            # 如果有弹窗、或者内容/状态发生改变，则唤醒屏幕
            if show_volume or \
               current_state.key != last_state_key or \
               current_state.signature != last_content_signature:
                screen_saver.wake()
            
            # 🆕 确定媒体是否活跃 (播放、暂停状态)
            # 只要有播放器占用 (active_player_type 不是 None)，即视为活跃状态，阻止息屏。
            is_media_active = active_player_type is not None

            # 传递媒体状态给 tick，仅在媒体非活跃状态 (停止/空闲) 下才允许息屏
            screen_saver.tick(is_media_active)

            # 3.5 刷新屏幕
            # 仅当参数变化或处于时钟模式（每秒刷新）时调用 display_text
            should_refresh = (display_args != last_display_args) or (current_state.is_clock)
            
            if should_refresh:
                display_text(display_ctx, *display_args)
                last_display_args = display_args
                last_state_key = current_state.key
                last_content_signature = current_state.signature

            time.sleep(1)

        except KeyboardInterrupt:
            break
        except Exception as e:
            logger.error(f"Main Loop Error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()
