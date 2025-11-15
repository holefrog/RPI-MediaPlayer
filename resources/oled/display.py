import time
import threading
import logging
import os
from luma.core.interface.serial import i2c
from luma.oled.device import ssd1306
from luma.core.render import canvas
from PIL import ImageFont, ImageDraw

# -------------------------------
# 配置
# -------------------------------
FONT_PATH = "./msyh.ttf"
FONT_SMALL_SIZE = 14
FONT_LARGE_SIZE = 22
DEFAULT_BRIGHTNESS = 255  # 默认亮度
DIM_BRIGHTNESS = 8        # 变暗亮度

logging.basicConfig(level=logging.INFO)

# -------------------------------
# OLED 初始化
# -------------------------------
serial = i2c(port=3, address=0x3C)
device = ssd1306(serial)

width = device.width
height = device.height

# -------------------------------
# 加载字体
# -------------------------------
def load_font(path, size):
    if os.path.isfile(path):
        return ImageFont.truetype(path, size)
    else:
        logging.warning(f"字体文件 {path} 不存在，使用默认字体")
        return ImageFont.load_default()

font_small = load_font(FONT_PATH, FONT_SMALL_SIZE)
font_large = load_font(FONT_PATH, FONT_LARGE_SIZE)

# -------------------------------
# 线程控制变量
# -------------------------------
current_scroll_thread = None
scroll_stop_event = threading.Event()

# -------------------------------
# 滚动缓存
# -------------------------------
scroll_cache = {}

# -------------------------------
# 亮度控制
# -------------------------------
def set_brightness(level: int):
    level = max(0, min(255, level))
    device.contrast(level)
    logging.info(f"Set brightness to {level}")

def restore_brightness():
    set_brightness(DEFAULT_BRIGHTNESS)
    logging.info(f"Restored brightness to {DEFAULT_BRIGHTNESS}")

# -------------------------------
# 显示控制
# -------------------------------
def turn_off_display():
    device.hide()
    logging.info("Display turned off")

def turn_on_display():
    device.show()
    restore_brightness()
    logging.info("Display turned on")

# -------------------------------
# 滚动文本函数
# -------------------------------
def scroll_text(top_text, bottom_text, large_font=False, scroll_speed=0.02, stop_event=None):
    top_font = font_small
    bottom_font = font_large if large_font else font_small

    with canvas(device) as draw:
        top_bbox = draw.textbbox((0, 0), top_text, font=top_font)
        top_width = top_bbox[2] - top_bbox[0]
        top_height = top_bbox[3] - top_bbox[1]
        top_x = (width - top_width) // 2
        top_y = (14 - top_height) // 2 - 1
        draw.text((top_x, top_y), top_text, font=top_font, fill=255)

    cache_key = (bottom_text, large_font)
    if cache_key not in scroll_cache:
        with canvas(device) as draw:
            bottom_bbox = draw.textbbox((0, 0), bottom_text, font=bottom_font)
            scroll_cache[cache_key] = bottom_bbox[2] - bottom_bbox[0]

    bottom_text_width = scroll_cache[cache_key]
    bottom_text = "  " + bottom_text + "  "

    while not (stop_event and stop_event.is_set()):
        for offset in range(0, bottom_text_width + width):
            if stop_event and stop_event.is_set():
                break
            with canvas(device) as draw:
                draw.text((top_x, top_y), top_text, font=top_font, fill=255)
                draw.text((width - offset, 20), bottom_text, font=bottom_font, fill=255)
            time.sleep(scroll_speed)

# -------------------------------
# 显示文本主函数
# -------------------------------
def display_text(top_text, bottom_text, large_font=False, scroll_speed=0.02, is_time_update=False):
    global current_scroll_thread, scroll_stop_event

    if current_scroll_thread and current_scroll_thread.is_alive():
        scroll_stop_event.set()
        current_scroll_thread.join()
    scroll_stop_event.clear()

    bottom_font = font_large if large_font else font_small
    with canvas(device) as draw:
        # 计算顶部文本位置
        top_font = font_small
        top_bbox = draw.textbbox((0, 0), top_text, font=top_font)
        top_width = top_bbox[2] - top_bbox[0]
        top_height = top_bbox[3] - top_bbox[1]
        top_x = (width - top_width) // 2
        top_y = (14 - top_height) // 2 - 1

        # 计算底部文本位置
        bottom_bbox = draw.textbbox((0, 0), bottom_text, font=bottom_font)
        bottom_text_width = bottom_bbox[2] - bottom_bbox[0]
        bottom_x = (width - bottom_text_width) // 2
        bottom_y = 20

        # 总是绘制顶部文本
        draw.text((top_x, top_y), top_text, font=top_font, fill=255)

        # 如果是时间更新，仅重绘底部时间区域
        if is_time_update:
            draw.rectangle((0, 20, width, height), fill=0)  # 清除底部区域
            draw.text((bottom_x, bottom_y), bottom_text, font=bottom_font, fill=255)
        else:
            # 正常显示，绘制底部文本（无需清除）
            draw.text((bottom_x, bottom_y), bottom_text, font=bottom_font, fill=255)

    # 处理滚动文本
    if bottom_text_width > width and not is_time_update:
        current_scroll_thread = threading.Thread(
            target=scroll_text,
            args=(top_text, bottom_text, large_font, scroll_speed, scroll_stop_event)
        )
        current_scroll_thread.start()

# -------------------------------
# 示例运行
# -------------------------------
if __name__ == "__main__":
    restore_brightness()
    display_text("顶部固定", "底部滚动文字测试，这段文字会滚动显示", large_font=True, scroll_speed=0.02)
    time.sleep(10)
    turn_off_display()
