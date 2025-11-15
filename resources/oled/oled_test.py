#!/usr/bin/env python3
# resources/oled/oled_test.py
# 
# 参数化的 OLED 测试脚本
#
# 用法:
# python3 oled_test.py --bus <bus_num> --address <0xXX> --width <w> --height <h>

import time
import argparse
import sys
from luma.core.interface.serial import i2c
from luma.oled.device import ssd1306
from luma.core.render import canvas
from PIL import ImageFont

def main():
    # ============================================
    # 1. 设置命令行参数
    # ============================================
    parser = argparse.ArgumentParser(description="OLED Test Script")
    parser.add_argument("--bus", type=int, required=True, help="I2C bus number (e.g., 1 or 3)")
    parser.add_argument("--address", type=str, required=True, help="I2C address (e.g., 0x3C)")
    parser.add_argument("--width", type=int, default=128, help="Display width (pixels)")
    parser.add_argument("--height", type=int, default=64, help="Display height (pixels)")
    args = parser.parse_args()

    # ============================================
    # 2. 解析 I2C 地址 (从 "0x3C" 字符串转为 0x3C 整数)
    # ============================================
    try:
        i2c_address = int(args.address, 16)
    except ValueError:
        print(f"错误: 无效的 I2C 地址格式: {args.address}. 必须是 0xXX 格式")
        sys.exit(1)

    # ============================================
    # 3. 初始化 I2C 设备
    # ============================================
    print(f"初始化 OLED: 总线(Bus)={args.bus}, 地址(Address)={args.address} ({i2c_address}), 分辨率={args.width}x{args.height}")
    try:
        serial = i2c(port=args.bus, address=i2c_address)
        device = ssd1306(serial, width=args.width, height=args.height)
    except Exception as e:
        print(f"错误: 初始化设备失败: {e}")
        print("请检查 I2C 总线、地址、硬件连接以及 config.ini 中的设置。")
        sys.exit(1)

    # ============================================
    # 4. 加载字体
    # ============================================
    try:
        font = ImageFont.load_default()
    except IOError:
        print("错误: 加载默认字体失败。请确保 PIL/Pillow 库已正确安装。")
        sys.exit(1)

    # ============================================
    # 5. 循环显示 (20 秒)
    # ============================================
    start_time = time.time()
    print("开始显示测试图案 (持续 20 秒)... (按 Ctrl+C 提前停止)")
    
    try:
        while True:
            elapsed = time.time() - start_time
            remaining = int(20 - elapsed)   # 剩余秒数，转为整数

            if remaining < 0:
                remaining = 0

            with canvas(device) as draw:
                draw.text((0, 0), "Hello OLED!", font=font, fill="white")
                draw.text((0, 20), "Test Script (20s)", font=font, fill="white")
                draw.text((0, 40), f"Countdown: {remaining}s", font=font, fill="white")

            # 到 20 秒退出
            if elapsed >= 20:
                print("测试完成。")
                break

            time.sleep(1)

    except KeyboardInterrupt:
        print("测试被用户中断。")
    except Exception as e:
        print(f"显示循环时出错: {e}")
    finally:
        # 清理屏幕
        try:
            device.clear()
        except Exception:
            pass

if __name__ == "__main__":
    main()
