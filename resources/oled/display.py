#!/usr/bin/env python
# resources/oled/display.py

import time
import threading
import logging
import os
from luma.core.interface.serial import i2c
from luma.oled.device import ssd1306
from luma.core.render import canvas
from PIL import ImageFont, ImageDraw

# ============================================
# 日志配置 (统一格式)
# ============================================
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(name)s] [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger("Display")

STATUS_FONT = ImageFont.load_default()

# -------------------------------
# 全局变量（由配置初始化）
# -------------------------------
_display_config = None
current_scroll_thread = None
scroll_stop_event = threading.Event()
scroll_cache = {}
_latest_volume = None
_current_scroll_signature = None

# -------------------------------
# 配置初始化函数
# -------------------------------
def init_display_config(display_config):
    """
    初始化显示配置（必须在使用其他函数前调用）
    
    Args:
        display_config: 来自 config.load_config()["display"] 的配置字典
    """
    global _display_config
    _display_config = display_config
    logger.info("Display 配置已加载:")
    for key, value in display_config.items():
        logger.info(f"  {key} = {value}")

def _get_config(key, default=None):
    """安全获取配置值"""
    if _display_config is None:
        logger.warning(f"Display 配置未初始化，使用默认值: {key}={default}")
        return default
    return _display_config.get(key, default)

# -------------------------------
# 辅助函数
# -------------------------------
def _load_font(path, size):
    if os.path.isfile(path):
        return ImageFont.truetype(path, size)
    else:
        logger.warning(f"字体文件 {path} 不存在，使用默认字体")
        return ImageFont.load_default()

def _draw_speaker_icon(draw, x, y, is_muted=False):
    draw.rectangle((x, y + 2, x + 2, y + 5), fill=255)
    draw.polygon([(x + 2, y + 2), (x + 6, y - 1), (x + 6, y + 8), (x + 2, y + 5)], fill=255)
    if is_muted:
        draw.line((x + 8, y + 1, x + 11, y + 6), fill=255, width=1)
        draw.line((x + 8, y + 6, x + 11, y + 1), fill=255, width=1)

def _draw_volume_bar(draw, width, height, volume):
    if volume is None: return
    bar_height = 12
    bar_y_start = height - bar_height
    draw.rectangle((0, bar_y_start, width, height), fill=0)

    vol = max(0, min(100, volume))
    is_muted = (vol == 0)
    vol_text = f"{vol}"

    _draw_speaker_icon(draw, 0, height - 10, is_muted)
    
    bbox = draw.textbbox((0, 0), vol_text, font=STATUS_FONT)
    text_w = bbox[2] - bbox[0]
    text_x = width - text_w
    text_y = height - 11 
    draw.text((text_x, text_y), vol_text, font=STATUS_FONT, fill=255)

    bar_start_x = 16
    bar_end_x = text_x - 4
    bar_width = bar_end_x - bar_start_x
    
    if bar_width > 0:
        fill_width = int((bar_width * vol) / 100)
        bar_top = height - 7
        bar_bottom = height - 3
        if not is_muted:
            draw.rectangle((bar_start_x, bar_top, bar_start_x + fill_width, bar_bottom), fill=255)

# -------------------------------
# OLED 初始化
# -------------------------------
def init_display(port: int, address: int, w: int, h: int, display_config: dict):
    """
    初始化 OLED 显示设备
    
    Args:
        port: I2C 总线编号
        address: I2C 地址
        w: 显示宽度
        h: 显示高度
        display_config: 显示配置字典（包含字体、亮度等）
    """
    try:
        logger.info(f"初始化 I2C: port={port}, address=0x{address:X}")
        serial = i2c(port=port, address=address)
        device = ssd1306(serial, width=w, height=h)
        
        # 从配置读取字体和亮度
        font_path = display_config.get("font_path", "./msyh.ttf")
        font_small_size = display_config.get("font_small_size", 14)
        font_large_size = display_config.get("font_large_size", 22)
        default_brightness = display_config.get("default_brightness", 255)
        dim_brightness = display_config.get("dim_brightness", 8)
        
        font_small = _load_font(font_path, font_small_size)
        font_large = _load_font(font_path, font_large_size)
        
        device.contrast(default_brightness)
        
        # 初始化全局配置
        init_display_config(display_config)
        
        return {
            "device": device, 
            "width": device.width, 
            "height": device.height,
            "font_small": font_small, 
            "font_large": font_large,
            "default_brightness": default_brightness, 
            "dim_brightness": dim_brightness
        }
    except Exception as e:
        logger.error(f"OLED 初始化失败: {e}")
        raise

def set_brightness(display_ctx: dict, level: int):
    display_ctx["device"].contrast(max(0, min(255, level)))

def restore_brightness(display_ctx: dict):
    set_brightness(display_ctx, display_ctx["default_brightness"])

def turn_off_display(display_ctx: dict):
    display_ctx["device"].hide()

def turn_on_display(display_ctx: dict):
    display_ctx["device"].show()
    restore_brightness(display_ctx)

# -------------------------------
# 滚动文本函数
# -------------------------------
def scroll_text(display_ctx: dict, top_text, bottom_text, large_font, scroll_speed, stop_event, top_align):
    device = display_ctx["device"]
    width = display_ctx["width"]
    height = display_ctx["height"]
    font_small = display_ctx["font_small"]
    font_large = display_ctx["font_large"]
    top_font = font_small
    bottom_font = font_large if large_font else font_small
    
    # 从配置读取滚动步进
    scroll_step = _get_config("scroll_step", 2)

    with canvas(device) as draw:
        top_bbox = draw.textbbox((0, 0), top_text, font=top_font)
        if top_align == "left": top_x = 0
        else: top_x = (width - (top_bbox[2] - top_bbox[0])) // 2
        top_y = (14 - (top_bbox[3] - top_bbox[1])) // 2 - 2

    cache_key = (bottom_text, large_font)
    if cache_key not in scroll_cache:
        with canvas(device) as draw:
            bbox = draw.textbbox((0, 0), bottom_text, font=bottom_font)
            scroll_cache[cache_key] = bbox[2] - bbox[0]
    bottom_text_width = scroll_cache[cache_key]

    while not (stop_event and stop_event.is_set()):
        for offset in range(0, bottom_text_width + width, scroll_step):
            if stop_event and stop_event.is_set(): break
            
            with canvas(device) as draw:
                draw.text((top_x, top_y), top_text, font=top_font, fill=255)
                draw.text((width - offset, 18), bottom_text, font=bottom_font, fill=255)
                _draw_volume_bar(draw, width, height, _latest_volume)
                
            time.sleep(scroll_speed)

# -------------------------------
# 显示文本主函数
# -------------------------------
def display_text(display_ctx, top_text, bottom_text, large_font=False, scroll_speed=0.02, is_time_update=False, volume=None, top_align="center"):
    global current_scroll_thread, scroll_stop_event
    global _latest_volume, _current_scroll_signature

    _latest_volume = volume
    device = display_ctx["device"]
    width = display_ctx["width"]
    height = display_ctx["height"]
    font_small = display_ctx["font_small"]
    font_large = display_ctx["font_large"]

    new_signature = (top_text, bottom_text, large_font, top_align)
    if (current_scroll_thread and current_scroll_thread.is_alive() 
        and new_signature == _current_scroll_signature):
        return

    if current_scroll_thread and current_scroll_thread.is_alive():
        scroll_stop_event.set()
        current_scroll_thread.join()
    scroll_stop_event.clear()
    
    _current_scroll_signature = new_signature
    top_font = font_small
    bottom_font = font_large if large_font else font_small
    
    with canvas(device) as draw:
        top_bbox = draw.textbbox((0, 0), top_text, font=top_font)
        if top_align == "left": top_x = 0
        else: top_x = (width - (top_bbox[2] - top_bbox[0])) // 2
        top_y = (14 - (top_bbox[3] - top_bbox[1])) // 2 - 2
        draw.text((top_x, top_y), top_text, font=top_font, fill=255)

        bottom_bbox = draw.textbbox((0, 0), bottom_text, font=bottom_font)
        bottom_w = bottom_bbox[2] - bottom_bbox[0]
        bottom_x = (width - bottom_w) // 2
        bottom_y = 18
        draw.text((bottom_x, bottom_y), bottom_text, font=bottom_font, fill=255)
        _draw_volume_bar(draw, width, height, _latest_volume)

    if bottom_w > width and not is_time_update:
        current_scroll_thread = threading.Thread(
            target=scroll_text,
            args=(display_ctx, top_text, bottom_text, large_font, scroll_speed, scroll_stop_event, top_align)
        )
        current_scroll_thread.start()
