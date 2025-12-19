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

start_time = time.time()

while True:
    with canvas(device) as draw:
        draw.text((0, 0), "Hello OLED!", font=font, fill="white")
        draw.text((0, 20), "Will quit in 20s", font=font, fill="white")
        draw.text((0, 40), time.strftime("%H:%M:%S"), font=font, fill="white")
    
    # 20 秒后退出
    if time.time() - start_time >= 20:
        break
    
    time.sleep(1)
