#!/usr/bin/env python
# resources/oled/config.py - 修复版：支持日志级别配置

import configparser
import os
import logging

# 动态获取当前脚本所在的绝对路径
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(BASE_DIR, "oled.ini")

def load_config():
    """
    加载完整配置文件
    
    Returns:
        dict: 包含所有配置的字典
        {
            "lms": (host_ip, host_port, player_id),
            "oled": (bus, address, width, height, log_level),
            "display": {...},
            "screensaver": {...},
            "volume": {...},
            "airplay": {...}
        }
    """
    
    # 检查配置文件是否存在
    if not os.path.exists(CONFIG_FILE):
        logging.error(f"错误：未找到配置文件 {CONFIG_FILE}")
        logging.error("请创建配置文件并填写必要信息")
        exit(1)
    
    config = configparser.ConfigParser()
    
    try:
        config.read(CONFIG_FILE)
    except Exception as e:
        logging.error(f"配置文件读取失败: {e}")
        exit(1)
    
    try:
        # ============================================
        # 1. LMS 服务器配置
        # ============================================
        host_ip = config.get("SERVER", "HOST_IP")
        host_port = config.get("SERVER", "HOST_Port")
        player_id = config.get("SERVER", "PLAYER_ID")
            
        # ============================================
        # 2. OLED 硬件配置
        # ============================================
        oled_bus = config.getint("OLED", "bus", fallback=3)
        oled_address_str = config.get("OLED", "address", fallback="0x3C")
        oled_width = config.getint("OLED", "width", fallback=128)
        oled_height = config.getint("OLED", "height", fallback=64)
        
        # 🆕 读取日志级别配置
        log_level_str = config.get("OLED", "log_level", fallback="INFO").upper()
        
        # 验证日志级别
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if log_level_str not in valid_levels:
            logging.warning(f"无效的日志级别: {log_level_str}，使用默认值 INFO")
            log_level_str = "INFO"
        
        # 转换为 logging 常量
        log_level = getattr(logging, log_level_str)
        
        # 将地址字符串转换为整数
        oled_address = int(oled_address_str, 16)
        
        # ============================================
        # 3. 显示配置
        # ============================================
        font_path = config.get("DISPLAY", "font_path", fallback=os.path.join(BASE_DIR, "msyh.ttf"))
        font_small_size = config.getint("DISPLAY", "font_small_size", fallback=14)
        font_large_size = config.getint("DISPLAY", "font_large_size", fallback=22)
        default_brightness = config.getint("DISPLAY", "default_brightness", fallback=255)
        dim_brightness = config.getint("DISPLAY", "dim_brightness", fallback=8)
        scroll_step = config.getint("DISPLAY", "scroll_step", fallback=2)
        scroll_speed_playing = config.getfloat("DISPLAY", "scroll_speed_playing", fallback=0.004)
        scroll_speed_static = config.getfloat("DISPLAY", "scroll_speed_static", fallback=0.02)
        
        # ============================================
        # 4. 屏保配置
        # ============================================
        dim_timeout = config.getint("SCREENSAVER", "dim_timeout", fallback=5)
        off_timeout = config.getint("SCREENSAVER", "off_timeout", fallback=900)
        
        # ============================================
        # 5. 音量配置
        # ============================================
        popup_duration = config.getfloat("VOLUME", "popup_duration", fallback=2.5)
        
        # ============================================
        # 6. AirPlay 配置
        # ============================================
        metadata_pipe = config.get("AIRPLAY", "metadata_pipe", fallback="/tmp/shairport-sync-metadata")
        
        # ============================================
        # 日志输出
        # ============================================
        logging.info("=" * 50)
        logging.info("配置加载成功")
        logging.info("=" * 50)
        logging.info(f"LMS 服务器: {host_ip}:{host_port}")
        logging.info(f"播放器 ID: {player_id}")
        logging.info(f"OLED: bus={oled_bus}, addr=0x{oled_address:X}, size={oled_width}x{oled_height}")
        logging.info(f"日志级别: {log_level_str}")
        logging.info(f"字体: {font_path} (小={font_small_size}, 大={font_large_size})")
        logging.info(f"亮度: 默认={default_brightness}, 暗={dim_brightness}")
        logging.info(f"滚动: 步进={scroll_step}, 播放={scroll_speed_playing}s, 静态={scroll_speed_static}s")
        logging.info(f"屏保: 暗={dim_timeout}s, 关={off_timeout}s")
        logging.info(f"音量弹窗: {popup_duration}s")
        logging.info(f"AirPlay 管道: {metadata_pipe}")
        logging.info("=" * 50)
        
        # ============================================
        # 返回配置字典
        # ============================================
        return {
            "lms": {
                "host_ip": host_ip,
                "host_port": host_port,
                "player_id": player_id,
            },
            "oled": {
                "bus": oled_bus,
                "address": oled_address,
                "width": oled_width,
                "height": oled_height,
                "log_level": log_level,  # 🆕 新增日志级别
            },
            "display": {
                "font_path": font_path,
                "font_small_size": font_small_size,
                "font_large_size": font_large_size,
                "default_brightness": default_brightness,
                "dim_brightness": dim_brightness,
                "scroll_step": scroll_step,
                "scroll_speed_playing": scroll_speed_playing,
                "scroll_speed_static": scroll_speed_static,
            },
            "screensaver": {
                "dim_timeout": dim_timeout,
                "off_timeout": off_timeout,
            },
            "volume": {
                "popup_duration": popup_duration,
            },
            "airplay": {
                "metadata_pipe": metadata_pipe,
            }
        }
        
    except (configparser.NoSectionError, configparser.NoOptionError) as e:
        logging.error(f"配置文件格式无效: {e}")
        logging.error("请确保 oled.ini 包含所有必需的 section")
        exit(1)

# 测试代码
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    print("\n=== 配置加载测试 ===\n")
    cfg = load_config()
    
    print(f"LMS 配置: {cfg['lms']}")
    print(f"OLED 配置: {cfg['oled']}")
    print(f"显示配置: {cfg['display']}")
    print(f"屏保配置: {cfg['screensaver']}")
    print(f"音量配置: {cfg['volume']}")
    print(f"AirPlay 配置: {cfg['airplay']}")
