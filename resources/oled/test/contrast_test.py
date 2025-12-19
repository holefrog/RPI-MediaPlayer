#!/usr/bin/env python3
import time
from luma.core.interface.serial import i2c
from luma.oled.device import ssd1306
from luma.core.render import canvas
from PIL import ImageFont

# 初始化 I2C (bus {{OLED_BUS}}, address {{OLED_ADDR}})
serial = i2c(port=3, address=0x3c)
device = ssd1306(serial, width=128, height=64)

# 字体
font = ImageFont.load_default()

# 从最亮到最暗
for brightness in range(255, -1, -1):
    # 设置亮度
    device.contrast(brightness)

    # 显示内容
    with canvas(device) as draw:
        draw.text((0, 0), "OLED Brightness Test", font=font, fill="white")
        draw.text((0, 20), f"Brightness: {brightness}", font=font, fill="white")
        draw.text((0, 40), time.strftime("%H:%M:%S"), font=font, fill="white")

    time.sleep(1)

