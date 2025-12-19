#!/usr/bin/env python3
import time
from luma.core.interface.serial import i2c
from luma.oled.device import ssd1306
from luma.core.render import canvas
from PIL import ImageFont, Image, ImageEnhance

# 初始化 I2C
serial = i2c(port=3, address=0x3c)
device = ssd1306(serial, width=128, height=64)

# 字体
font = ImageFont.load_default()

# 创建一张原始图像（作为模板）
base_img = Image.new("1", (device.width, device.height), 0)
with canvas(device) as draw:
    draw.text((0, 0), "OLED Fade-out Test", font=font, fill="white")
    draw.text((0, 20), "Brightness Demo", font=font, fill="white")
    draw.text((0, 40), time.strftime("%H:%M:%S"), font=font, fill="white")

# 为了获取模板，重新画一遍
with canvas(device) as draw:
    draw.text((0, 0), "OLED Fade-out Test", font=font, fill="white")
    draw.text((0, 20), "Brightness Demo", font=font, fill="white")
    draw.text((0, 40), time.strftime("%H:%M:%S"), font=font, fill="white")

# 获取当前画面截图作为基准
base_img = device.snapshot()

# 从亮到暗，倍数从 1.0 -> 0.0
steps = 40
for i in range(steps, -1, -1):
    factor = i / steps  # 亮度比例 1.0 → 0.0

    enhancer = ImageEnhance.Brightness(base_img)
    img = enhancer.enhance(factor)

    device.display(img)

    time.sleep(0.1)

