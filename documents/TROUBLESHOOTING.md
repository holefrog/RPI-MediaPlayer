# 🛠️ RPI MediaPlayer 故障排查指南

本指南提供系统化的问题解决方案，帮助您快速定位和修复常见问题。

---

## 📋 目录

1. [部署和连接问题](#1-部署和连接问题)
2. [硬件检测问题](#2-硬件检测问题)
3. [音频服务问题](#3-音频服务问题)
4. [音源播放问题](#4-音源播放问题)
5. [音量控制问题](#5-音量控制问题)
6. [OLED 显示问题](#6-oled-显示问题)
7. [蓝牙配对问题](#7-蓝牙配对问题)
8. [日志和调试](#8-日志和调试)

---

## 1. 部署和连接问题

### ❌ SSH 连接失败

**症状：**
```bash
ssh: connect to host rpi.local port 22: Connection refused
# 或
ssh: Could not resolve hostname rpi.local
```

#### 🔍 排查步骤

<details>
<summary><strong>原因 1：网络问题</strong></summary>

```bash
# 1. 检查树莓派是否在线
ping rpi.local

# 2. 如果无法解析主机名，尝试使用 IP 地址
ping 192.168.1.xxx

# 3. 扫描网络找到树莓派
nmap -sn 192.168.1.0/24 | grep -i raspberry

# 4. 在 macOS/Linux 上查看 mDNS 设备
dns-sd -B _ssh._tcp
```

**✅ 解决方案：**
- 确保树莓派和电脑在**同一网络**
- 如果使用 WiFi，检查路由器 DHCP 分配的 IP
- 使用 `ssh player@<IP地址>` 替代 `rpi.local`
- 确认 Raspberry Pi Imager 配置的网络信息正确

</details>

<details>
<summary><strong>原因 2：SSH 服务未启动</strong></summary>

```bash
# 在树莓派上（需要显示器/键盘）
sudo systemctl status ssh

# 如果未运行，启动服务
sudo systemctl enable ssh --now
```

**✅ 解决方案：**
- 使用 Raspberry Pi Imager 时勾选 **"Enable SSH"**
- 或在 boot 分区创建空文件 `ssh`（无扩展名）
- 重新烧录系统并确保启用 SSH

</details>

<details>
<summary><strong>原因 3：SSH 密钥权限错误</strong></summary>

```bash
# 验证密钥权限
ls -l ./rpi_keys/id_rpi
# 应该显示: -rw------- (权限 600)

# 如果权限不对，修复
chmod 600 ./rpi_keys/id_rpi

# 测试详细连接日志
ssh -i ./rpi_keys/id_rpi -v player@rpi.local
```

**✅ 解决方案：**
- 确保私钥权限为 `600`（仅所有者可读写）
- 重新运行 `ssh-copy-id -i ./rpi_keys/id_rpi.pub player@rpi.local`
- 检查 `~/.ssh/authorized_keys` 是否包含公钥

</details>

<details>
<summary><strong>原因 4：主机密钥冲突</strong></summary>

**症状：**
```
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

```bash
# 删除旧的主机密钥
ssh-keygen -R rpi.local
ssh-keygen -R 192.168.1.xxx  # 如果使用过 IP

# 重新连接时接受新指纹
ssh -i ./rpi_keys/id_rpi player@rpi.local
```

**✅ 解决方案：**
这通常发生在重新烧录系统后，删除旧密钥即可。

</details>

---

### ❌ setup.sh 运行失败

**症状：**
```bash
[ERROR] 上传库文件失败
# 或
[ERROR] 无法创建远程目录
```

#### 🔍 完整检查清单

```bash
# 1️⃣ 验证本地文件完整性
ls -R lib/ modules/ templates/ resources/
# 应该看到所有必需文件

# 2️⃣ 检查 config.ini 格式
cat config.ini
# 确保没有语法错误（[section] 和 key=value）

# 3️⃣ 测试 SCP 连接
scp -i ./rpi_keys/id_rpi config.ini player@rpi.local:~/test_upload

# 4️⃣ 检查远程磁盘空间
ssh -i ./rpi_keys/id_rpi player@rpi.local "df -h"
# 确保至少有 2GB 可用空间

# 5️⃣ 检查脚本执行权限
ls -l setup.sh stage_*.sh
chmod +x setup.sh stage_*.sh
```

**常见问题和解决方案：**

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 权限错误 | 脚本不可执行 | `chmod +x setup.sh stage_*.sh` |
| 配置格式错误 | `config.ini` 语法问题 | 检查 `[section]` 和 `key=value` 格式 |
| 磁盘空间不足 | SD 卡容量小 | 使用至少 16GB 的 SD 卡 |
| 网络超时 | SSH 连接不稳定 | 增加 `[timeouts] ssh_connect` 值 |

---

### ❌ 重启后无法重新连接

**症状：**
```
等待 RPi 重启上线 (超时: 180s)...
[ERROR] RPi 重启超时
```

#### 🔍 排查步骤

**步骤 1：延长等待时间**（适用于慢速 SD 卡）

```ini
# 编辑 config.ini
[timeouts]
reboot_wait = 300          # 从 180 秒延长到 300 秒
reboot_poll_interval = 5   # 每 5 秒检查一次
```

**步骤 2：手动检查启动状态**

```bash
# 从另一个终端连接（如果可能）
ssh -i ./rpi_keys/id_rpi player@rpi.local

# 查看启动日志
journalctl -b -0 | tail -100

# 检查启动错误
journalctl -p err -b
```

**步骤 3：检查硬件问题**

| 检查项 | 正常状态 | 异常状态 | 解决方案 |
|--------|---------|---------|----------|
| 🔴 红色 LED | 常亮 | 闪烁/熄灭 | 电源不足，换 5V 3A 电源 |
| 🟢 绿色 LED | 闪烁 | 不闪烁 | SD 卡问题，重新烧录系统 |
| 🌡️ 温度 | < 70°C | > 80°C | 添加散热片或风扇 |
| 💾 SD 卡 | 正常插入 | 接触不良 | 重新插拔 SD 卡 |

---

## 2. 硬件检测问题

### ❌ WM8960 声卡未检测到

**症状：**
```bash
aplay -l
# 输出: no soundcards found
```

#### 🔍 完整排查流程

<details>
<summary><strong>步骤 1：验证 /boot/config.txt 配置</strong></summary>

```bash
# SSH 连接到树莓派
ssh -i ./rpi_keys/id_rpi player@rpi.local

# 检查配置
cat /boot/firmware/config.txt | grep -E "i2s|audio|wm8960"

# 应该包含以下内容：
# dtparam=i2s=on
# dtparam=audio=off
# dtoverlay=wm8960-soundcard
```

**如果缺失配置：**

```bash
sudo nano /boot/firmware/config.txt

# 添加以下行（如果没有）
dtparam=i2s=on
dtparam=audio=off
dtoverlay=wm8960-soundcard

# 保存后重启
sudo reboot
```

</details>

<details>
<summary><strong>步骤 2：检查物理连接</strong></summary>

**WM8960 接线验证表：**

| WM8960 引脚 | RPi 引脚 | GPIO | 功能 | 电压 |
|------------|---------|------|------|------|
| 5V | 2 或 4 | - | 电源 | 5V |
| GND | 6 或 9 | - | 地 | 0V |
| SDA | 3 | GPIO2 | I2C 数据 | 3.3V |
| SCL | 5 | GPIO3 | I2C 时钟 | 3.3V |
| CLK | 12 | GPIO18 | I2S 位时钟 | 3.3V |
| LRCLK | 35 | GPIO19 | I2S 帧时钟 | 3.3V |
| DAC | 40 | GPIO21 | I2S 数据输出 | 3.3V |

**验证 I2C 连接：**

```bash
# 1. 列出 I2C 设备
ls /dev/i2c-*
# 应该显示: /dev/i2c-1

# 2. 扫描 I2C 地址
sudo i2cdetect -y 1

# 期望输出（WM8960 地址 0x1a）：
#      0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
# 00:          -- -- -- -- -- -- -- -- -- -- -- -- -- 
# 10: -- -- -- -- -- -- -- -- -- -- UU -- -- -- -- -- 
# 20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
```

**⚠️ 如果看不到 `UU`：**
- 检查杜邦线是否松动
- 确认 VCC 接 5V，不是 3.3V
- 确认 SDA/SCL 接对应的 GPIO2/GPIO3

</details>

<details>
<summary><strong>步骤 3：检查内核模块</strong></summary>

```bash
# 查看已加载的音频模块
lsmod | grep snd

# 期望看到：
# snd_soc_wm8960        # WM8960 驱动
# snd_soc_bcm2835_i2s   # I2S 接口

# 如果没有，手动加载
sudo modprobe snd_soc_wm8960
sudo modprobe snd_soc_bcm2835_i2s

# 检查加载结果
lsmod | grep wm8960
```

</details>

<details>
<summary><strong>步骤 4：查看 dmesg 日志</strong></summary>

```bash
# 查看 WM8960 相关日志
dmesg | grep -i wm8960

# 成功的日志示例：
# [    6.123456] wm8960 1-001a: WM8960 Audio Codec
# [    6.234567] asoc-simple-card soc_sound: wm8960-hifi <-> 20203000.i2s mapping ok

# 错误日志示例：
# [    6.123456] wm8960: probe of 1-001a failed with error -121
#                                                            ^^^
#                                                 -121 = I2C 通信错误
```

**常见错误代码：**

| 错误代码 | 含义 | 解决方案 |
|---------|------|----------|
| -121 | I2C 通信错误 | 检查 SDA/SCL 接线 |
| -110 | 设备超时 | 检查电源供电 |
| -2 | 设备不存在 | 检查 dtoverlay 配置 |

</details>

<details>
<summary><strong>步骤 5：排除硬件故障</strong></summary>

```bash
# 测试音频播放（如果声卡已检测到）
speaker-test -t wav -c 2 -D plughw:wm8960soundcard

# 按 Ctrl+C 停止
```

**如果仍然失败：**

1. **检查 WM8960 型号**
   - 确认是 **Waveshare WM8960 Sound Board**
   - 不是 WM8960 Audio HAT（接线不同）

2. **更换杜邦线**
   - I2C 通信对线材质量敏感
   - 使用短且质量好的杜邦线

3. **检查树莓派兼容性**
   - 推荐使用 **Raspberry Pi 4B**
   - 其他型号可能需要不同配置

</details>

**📖 详细接线图：** [`documents/HW_WM8960.md`](documents/HW_WM8960.md)

---

### ❌ OLED 显示屏无显示

**症状：**
- OLED 屏幕完全黑屏
- 或显示测试图案后不更新

#### 🔍 完整排查流程

<details>
<summary><strong>步骤 1：验证 I2C 总线配置</strong></summary>

```bash
# 检查 /boot/config.txt 中的 GPIO I2C 配置
cat /boot/firmware/config.txt | grep i2c-gpio

# 应该包含：
# dtoverlay=i2c-gpio,bus=3,i2c_gpio_sda=4,i2c_gpio_scl=5
```

**如果缺失：**

```bash
sudo nano /boot/firmware/config.txt

# 添加这行
dtoverlay=i2c-gpio,bus=3,i2c_gpio_sda=4,i2c_gpio_scl=5

# 保存并重启
sudo reboot
```

</details>

<details>
<summary><strong>步骤 2：验证 I2C 设备</strong></summary>

```bash
# 1. 列出 I2C 总线
ls /dev/i2c-*
# 应该显示: /dev/i2c-1 和 /dev/i2c-3

# 2. 扫描 I2C-3 总线
sudo i2cdetect -y 3

# 期望输出（OLED 地址 0x3c）：
#      0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
# 00:          -- -- -- -- -- -- -- -- -- -- -- -- -- 
# 10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
# 20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
# 30: -- -- -- -- -- -- -- -- -- -- -- -- 3c -- -- --
```

**OLED 接线验证表：**

| OLED 引脚 | RPi 引脚 | GPIO | 说明 |
|----------|---------|------|------|
| VCC | 1 | - | 3.3V 电源 |
| GND | 9 | - | 地 |
| SDA | 7 | GPIO4 | I2C 数据 |
| SCL | 29 | GPIO5 | I2C 时钟 |

**如果看不到 0x3c：**

```bash
# 尝试扫描 0x3d 地址
sudo i2cdetect -y 3

# 如果设备地址是 0x3d，修改配置
nano ~/rpi-mediaplayer/oled_app/oled.ini
# 修改: address = 0x3D

# 重启服务
systemctl --user restart oled
```

</details>

<details>
<summary><strong>步骤 3：手动测试 OLED</strong></summary>

```bash
# 1. 激活 Python 虚拟环境
source ~/.venv/oled/bin/activate

# 2. 运行测试脚本（显示 20 秒）
python3 /usr/local/bin/oled_display.py

# 3. 如果看到错误，检查库安装
pip list | grep luma

# 期望看到：
# luma.oled      3.13.0

# 如果没有，重新安装
pip install --upgrade luma.oled
```

**测试成功标准：**
- ✅ OLED 显示 "Hello OLED!"
- ✅ 显示当前时间并每秒更新
- ✅ 20 秒后自动退出

</details>

<details>
<summary><strong>步骤 4：检查 OLED 服务日志</strong></summary>

```bash
# 查看服务状态
systemctl --user status oled

# 查看详细日志
journalctl --user -u oled -n 50

# 实时日志
journalctl --user -u oled -f
```

**常见错误和解决方案：**

| 错误信息 | 原因 | 解决方案 |
|---------|------|----------|
| `KeyError: 'PLAYER_MAC'` | Squeezelite 未启动 | 检查 `systemctl --user status squeezelite` |
| `PermissionError: /dev/i2c-3` | I2C 权限问题 | `sudo usermod -aG i2c $USER` 然后重启 |
| `OSError: cannot open resource` | 字体文件缺失 | `ls ~/rpi-mediaplayer/oled_app/msyh.ttf` |
| `OSError: [Errno 121]` | I2C 通信错误 | 检查接线，降低 I2C 速度 |

</details>

<details>
<summary><strong>步骤 5：降低 I2C 速度（如果通信错误）</strong></summary>

```bash
# 编辑 boot 配置
sudo nano /boot/firmware/config.txt

# 修改 i2c-gpio 行，添加速度参数
dtoverlay=i2c-gpio,bus=3,i2c_gpio_sda=4,i2c_gpio_scl=5,i2c_gpio_delay_us=2

# 保存并重启
sudo reboot
```

</details>

**📖 详细接线图：** [`documents/HW_SSD1306.md`](documents/HW_SSD1306.md)

---

## 3. 音频服务问题

### ❌ PipeWire 未启动

**症状：**
```bash
pactl info
# 输出: Connection failure: Connection refused
```

#### 🔍 排查和修复

<details>
<summary><strong>方法 1：检查服务状态</strong></summary>

```bash
# 查看 PipeWire 相关服务
systemctl --user status pipewire pipewire-pulse wireplumber

# 如果未运行，启动服务
systemctl --user start pipewire pipewire-pulse wireplumber

# 启用开机自启
systemctl --user enable pipewire pipewire-pulse wireplumber
```

</details>

<details>
<summary><strong>方法 2：检查用户 Linger</strong></summary>

```bash
# 查看 linger 状态
loginctl show-user $USER -p Linger

# 应该显示: Linger=yes

# 如果不是，启用 linger
sudo loginctl enable-linger $USER

# 验证
loginctl show-user $USER -p Linger
```

**什么是 Linger？**
- Linger 允许用户服务在用户未登录时继续运行
- 对于音频服务至关重要

</details>

<details>
<summary><strong>方法 3：重置 PipeWire</strong></summary>

```bash
# 1. 停止所有 PipeWire 服务
systemctl --user stop pipewire pipewire-pulse wireplumber

# 2. 清除配置缓存
rm -rf ~/.local/state/pipewire/
rm -rf ~/.config/pipewire/

# 3. 重启服务
systemctl --user restart pipewire pipewire-pulse wireplumber

# 4. 等待 5 秒后验证
sleep 5
pactl info
```

</details>

<details>
<summary><strong>方法 4：检查运行时目录</strong></summary>

```bash
# 验证 XDG_RUNTIME_DIR 存在
echo $XDG_RUNTIME_DIR
ls -ld /run/user/$(id -u)

# 应该显示: drwx------ ... /run/user/1000

# 如果不存在或权限错误
sudo mkdir -p /run/user/$(id -u)
sudo chown $USER:$USER /run/user/$(id -u)
sudo chmod 700 /run/user/$(id -u)
```

</details>

---

### ❌ 音频输出设备错误

**症状：**
```bash
pactl list sinks
# 输出显示 HDMI 而非 WM8960
```

#### ✅ 强制使用 WM8960

```bash
# 1. 查找 WM8960 sink 名称
pactl list short sinks | grep wm8960
# 输出示例: 0   alsa_output.platform-wm8960-soundcard.analog-stereo

# 2. 设置为默认
pactl set-default-sink alsa_output.platform-wm8960-soundcard.analog-stereo

# 3. 禁用 HDMI 音频（可选）
pactl suspend-sink alsa_output.platform-vc4-hdmi-0.hdmi-stereo 1
pactl suspend-sink alsa_output.platform-vc4-hdmi-1.hdmi-stereo 1

# 4. 验证当前默认 sink
pactl info | grep "Default Sink"
```

#### 🔧 持久化配置（自动脚本）

```bash
# volume.sh 已包含此功能
/usr/local/bin/volume.sh init

# 查看详细状态
/usr/local/bin/volume.sh status
```

---

## 4. 音源播放问题

### ❌ Squeezelite 无法连接 LMS

**症状：**
```bash
journalctl --user -u squeezelite -n 20
# 输出: Failed to connect to server 192.168.50.210:3483
```

#### 🔍 排查步骤

<details>
<summary><strong>步骤 1：验证网络连通性</strong></summary>

```bash
# 1. Ping LMS 服务器
ping -c 4 192.168.50.210

# 2. 检查端口是否开放
nc -zv 192.168.50.210 3483

# 期望输出: Connection to 192.168.50.210 3483 port [tcp/*] succeeded!

# 3. 从 LMS 服务器 ping 树莓派
# (在 LMS 服务器上执行)
ping rpi.local
```

</details>

<details>
<summary><strong>步骤 2：检查配置</strong></summary>

```bash
# 查看 Squeezelite 启动参数
systemctl --user cat squeezelite | grep ExecStart

# 验证服务器 IP 是否正确
cat ~/installer/config.ini | grep server

# 应该显示: server=192.168.50.210
```

**如果 IP 错误：**

```bash
# 编辑配置
nano ~/installer/config.ini
# 修改 [squeezelite] server=正确的IP

# 重新部署或手动更新
/usr/local/bin/squeezelite.sh
```

</details>

<details>
<summary><strong>步骤 3：检查 LMS 服务器</strong></summary>

**在 LMS 服务器上：**

1. 访问 LMS Web 界面：`http://192.168.50.210:9000`
2. 检查 **Settings → Player → Authorized Players**
3. 确认允许新播放器连接
4. 查看 LMS 日志：`/var/log/squeezeboxserver/server.log`

</details>

<details>
<summary><strong>步骤 4：重启 Squeezelite</strong></summary>

```bash
# 重启服务
systemctl --user restart squeezelite

# 查看实时日志
journalctl --user -u squeezelite -f

# 期望看到：
# [INFO] Connected to server 192.168.50.210:3483
# [INFO] Player: RPI-Squeeze [02:xx:xx:xx:xx:xx]
```

</details>

---

### ❌ AirPlay 无法连接

**症状：**
- iOS 设备 AirPlay 列表中看不到树莓派
- 或连接后无声音

#### 🔍 排查步骤

<details>
<summary><strong>步骤 1：检查 Shairport-Sync 服务</strong></summary>

```bash
# 查看服务状态
systemctl --user status shairport-sync

# 如果未运行，启动服务
systemctl --user restart shairport-sync

# 查看日志
journalctl --user -u shairport-sync -f
```

</details>

<details>
<summary><strong>步骤 2：检查网络和端口</strong></summary>

```bash
# 1. 确认监听端口
sudo netstat -tuln | grep 5000

# 期望输出: tcp 0 0 0.0.0.0:5000 0.0.0.0:* LISTEN

# 2. 如果端口被占用，修改配置
nano ~/installer/config.ini
# 修改 [airplay] port = 5001

# 3. 重新部署
cd ~/installer && sudo ./stage_2.sh
```

</details>

<details>
<summary><strong>步骤 3：检查 mDNS 服务</strong></summary>

```bash
# 1. 验证 Avahi (mDNS) 运行中
systemctl status avahi-daemon

# 如果未运行
sudo systemctl enable avahi-daemon --now

# 2. 检查 AirPlay 服务广播
avahi-browse -a | grep -i airplay

# 期望看到:
# + wlan0 IPv4 RPI-AirPlay                          _raop._tcp           local
```

</details>

<details>
<summary><strong>步骤 4：检查配置文件</strong></summary>

```bash
# 查看 Shairport-Sync 配置
cat /etc/shairport-sync/shairport-sync.conf

# 验证关键设置：
# general {
#     name = "RPI-AirPlay";
#     port = 5000;
#     output_backend = "alsa";
# };
```

</details>

<details>
<summary><strong>步骤 5：元数据管道验证</strong></summary>

```bash
# 1. 检查管道是否存在
ls -l /tmp/shairport-sync-metadata

# 应该显示: prw-rw-rw- ... /tmp/shairport-sync-metadata
#            ^
#            p = named pipe (FIFO)

# 2. 如果不存在或权限错误，重新创建
sudo rm -f /tmp/shairport-sync-metadata
sudo mkfifo /tmp/shairport-sync-metadata
sudo chmod 666 /tmp/shairport-sync-metadata

# 3. 重启服务
systemctl --user restart shairport-sync

# 4. 测试管道读取
timeout 5 cat /tmp/shairport-sync-metadata
# 播放 AirPlay 音频时应该看到元数据输出
```

</details>

---

### ❌ 蓝牙设备无法发现

**症状：**
- 手机搜索不到 `RPI-Bluetooth`
- 或可见但无法配对

#### 🔍 完整排查流程

<details>
<summary><strong>步骤 1：检查蓝牙硬件</strong></summary>

```bash
# 1. 验证蓝牙控制器
hciconfig

# 期望输出:
# hci0:   Type: Primary  Bus: UART
#         BD Address: XX:XX:XX:XX:XX:XX  ACL MTU: 1021:8  SCO MTU: 64:1
#         UP RUNNING

# 2. 如果显示 DOWN，启用蓝牙
sudo hciconfig hci0 up

# 3. 验证状态
hciconfig hci0 | grep UP
# 应该显示: UP RUNNING
```

</details>

<details>
<summary><strong>步骤 2：检查软阻塞</strong></summary>

```bash
# 查看 rfkill 状态
sudo rfkill list

# 期望输出:
# 0: phy0: Wireless LAN
#     Soft blocked: no
#     Hard blocked: no
# 1: hci0: Bluetooth
#     Soft blocked: no    ← 重要
#     Hard blocked: no

# 如果蓝牙被 soft blocked，解除阻塞
sudo rfkill unblock bluetooth

# 验证
sudo rfkill list bluetooth
```

</details>

<details>
<summary><strong>步骤 3：检查蓝牙服务</strong></summary>

```bash
# 1. 系统蓝牙服务
systemctl status bluetooth

# 2. 自动配对服务
systemctl status bluetooth-a2dp-autopair

# 如果未运行
sudo systemctl restart bluetooth
sudo systemctl restart bluetooth-a2dp-autopair

# 查看自动配对日志
journalctl -u bluetooth-a2dp-autopair -f
```

</details>

<details>
<summary><strong>步骤 4：使用 bluetoothctl 调试</strong></summary>

```bash
# 进入交互模式
bluetoothctl

# 在 bluetoothctl 中执行：
power on
discoverable on
pairable on
agent NoInputNoOutput
default-agent
show

# 期望看到：
# Controller XX:XX:XX:XX:XX:XX (public)
#     Name: RPI-Bluetooth
#     Alias: RPI-Bluetooth
#     Powered: yes
#     Discoverable: yes        ← 重要
#     Pairable: yes            ← 重要
```

**保持这个终端开启，从手机搜索蓝牙设备**

</details>

<details>
<summary><strong>步骤 5：检查自动配对代理</strong></summary>

```bash
# 1. 查看 bt-agent 进程
ps aux | grep bt-agent

# 期望看到：
# root ... bt-agent -c NoInputNoOutput -p /home/player/bluetooth/pins.txt

# 2. 如果没有运行，检查 PIN 文件
cat ~/bluetooth/pins.txt
# 应该显示: * *

# 3. 手动启动测试
bt-agent -c NoInputNoOutput -p ~/bluetooth/pins.txt &

# 4. 或重启服务
sudo systemctl restart bluetooth-a2dp-autopair
```

</details>

<details>
<summary><strong>步骤 6：清除配对缓存</strong></summary>

```bash
# 1. 进入 bluetoothctl
bluetoothctl

# 2. 列出已配对设备
devices

# 3. 删除所有已配对设备
remove XX:XX:XX:XX:XX:XX  # 替换为实际 MAC 地址

# 或使用脚本批量删除
for dev in $(bluetoothctl devices | awk '{print $2}'); do
    bluetoothctl remove $dev
done

# 4. 重启蓝牙服务
sudo systemctl restart bluetooth
```

</details>

#### 📊 蓝牙配对失败日志分析

```bash
# 查看详细日志
journalctl -u bluetooth -f
```

**常见错误和解决方案：**

| 错误信息 | 原因 | 解决方案 |
|---------|------|----------|
| `Authentication Failed (0x05)` | PIN 码不匹配 | 检查 `~/bluetooth/pins.txt` 内容为 `* *` |
| `Connection Timeout` | 信号弱或干扰 | 移除附近其他蓝牙设备 |
| `br-connection-create-socket` | 已有旧配对记录 | 删除 `/var/lib/bluetooth/*/*` 并重启 |
| `Operation not permitted` | 权限问题 | 确保 bt-agent 以 root 运行 |

**📖 详细蓝牙配对策略：** [`documents/BLUETOOTH_TIPS.md`](documents/BLUETOOTH_TIPS.md)

---

## 5. 音量控制问题

### ❌ 音量过小或听不到声音

#### 🔍 完整排查流程

<details>
<summary><strong>步骤 1：检查硬件音量（WM8960 ALSA）</strong></summary>

```bash
# 1. 查看所有音量控制
amixer -c 0 contents

# 2. 设置关键控制到最大
amixer -c 0 sset 'Speaker' 100%
amixer -c 0 sset 'Playback' 100%
amixer -c 0 sset 'Speaker Playback Volume' 100%
amixer -c 0 sset 'PCM Playback Volume' 100%

# 3. 确保输出混音器已启用
amixer -c 0 sset 'Left Output Mixer PCM' on
amixer -c 0 sset 'Right Output Mixer PCM' on

# 4. 禁用 -6dB 衰减（重要！）
amixer -c 0 sset 'PCM Playback -6dB' off
```

**音量控制对照表：**

| 控制名称 | 推荐值 | 说明 |
|---------|-------|------|
| Speaker | 95% | 主音量 |
| Playback | 95% | 播放音量 |
| PCM Playback Volume | 95% | PCM 音量 |
| Left/Right Output Mixer PCM | on | 启用输出 |
| PCM Playback -6dB | off | 禁用衰减 |

</details>

<details>
<summary><strong>步骤 2：检查 PipeWire 软件音量</strong></summary>

```bash
# 1. 查看当前音量
pactl get-sink-volume @DEFAULT_SINK@

# 2. 设置到 100%
pactl set-sink-volume @DEFAULT_SINK@ 100%

# 3. 确保未静音
pactl set-sink-mute @DEFAULT_SINK@ 0

# 4. 查看详细信息
pactl list sinks | grep -A 10 "Name: alsa_output"
```

</details>

<details>
<summary><strong>步骤 3：运行音量初始化脚本</strong></summary>

```bash
# 执行完整初始化
/usr/local/bin/volume.sh init

# 查看状态
/usr/local/bin/volume.sh status

# 期望输出:
# [INFO] 当前音量: 100%
# [INFO] 当前 sink 状态:
#     Name: alsa_output.platform-wm8960-soundcard.analog-stereo
#     Volume: front-left: 65536 / 100% / 0.00 dB
#     Mute: no
```

</details>

<details>
<summary><strong>步骤 4：测试音频播放</strong></summary>

```bash
# 1. 播放测试音
speaker-test -t wav -c 2

# 应该听到 "Front Left, Front Right" 的声音
# 按 Ctrl+C 停止

# 2. 如果听到声音，说明硬件正常
# 继续检查各音源的音量设置
```

</details>

<details>
<summary><strong>步骤 5：检查物理连接</strong></summary>

**如果仍然无声音：**

| 检查项 | 验证方法 | 解决方案 |
|--------|---------|----------|
| 🔌 扬声器连接 | 检查 3.5mm 插头 | 确保插入 WM8960 输出端口 |
| 🔋 有源音箱电源 | 检查电源指示灯 | 确保音箱已开启 |
| 🎚️ 音箱音量 | 调节音箱本身旋钮 | 确保音箱音量不为 0 |
| 🔊 输出端口 | 检查 WM8960 标签 | 确认使用正确的输出端口 |

</details>

<details>
<summary><strong>步骤 6：验证 WM8960 是否真正被使用</strong></summary>

```bash
# 1. 列出所有音频设备
aplay -L | grep -A 2 wm8960

# 2. 尝试直接播放到 WM8960
aplay -D plughw:wm8960soundcard /usr/share/sounds/alsa/Front_Center.wav

# 3. 如果能听到声音，说明硬件正常
# 问题在于 PipeWire 路由配置
```

</details>

---

### ❌ 音量无法调节

**症状：**
- 运行 `volume.sh up` 无效
- 或 AirPlay/蓝牙音量调节不响应

#### 🔍 排查步骤

<details>
<summary><strong>问题 1：PipeWire 音量无响应</strong></summary>

```bash
# 1. 测试音量命令
pactl set-sink-volume @DEFAULT_SINK@ 50%
pactl get-sink-volume @DEFAULT_SINK@

# 2. 如果返回的音量不对，检查 sink 是否正确
pactl list sinks short

# 3. 手动指定 sink 名称
SINK_NAME="alsa_output.platform-wm8960-soundcard.analog-stereo"
pactl set-sink-volume $SINK_NAME 50%
pactl get-sink-volume $SINK_NAME
```

</details>

<details>
<summary><strong>问题 2：蓝牙音量不同步</strong></summary>

```bash
# 查看蓝牙音量（需要替换 MAC 地址）
dbus-send --system --print-reply \
    --dest=org.bluez \
    /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX/fd1 \
    org.freedesktop.DBus.Properties.Get \
    string:org.bluez.MediaTransport1 \
    string:Volume

# 如果无法获取，检查蓝牙配置
cat /etc/bluetooth/main.conf | grep -i volume
```

**蓝牙音量配置：**

```ini
[General]
# 确保包含这些配置
Class = 0x240414
ControllerMode = dual
```

</details>

<details>
<summary><strong>问题 3：AirPlay 音量固定</strong></summary>

**说明：** AirPlay 音量由 iOS 设备控制，树莓派只接收音频流

**验证方式：**

```bash
# 查看 Shairport-Sync 配置
cat /etc/shairport-sync/shairport-sync.conf | grep -A 5 "volume"

# 应该看到：
# volume = {
#     initial_volume = 60;
#     control = "yes";    ← 必须为 yes
# };
```

**如果 `control = "no"`：**

```bash
# 编辑配置文件
sudo nano /etc/shairport-sync/shairport-sync.conf

# 修改为:
# control = "yes";

# 重启服务
systemctl --user restart shairport-sync
```

</details>

---

## 6. OLED 显示问题

### ❌ OLED 无内容更新

**症状：**
- OLED 显示 "System Ready" 后不再更新
- 或显示错误信息

#### 🔍 排查步骤

<details>
<summary><strong>步骤 1：检查 OLED 服务日志</strong></summary>

```bash
# 查看最近 50 行日志
journalctl --user -u oled -n 50

# 实时日志
journalctl --user -u oled -f

# 查看错误日志
journalctl --user -u oled -p err
```

</details>

#### 📊 常见错误分析

<details>
<summary><strong>错误 1：无法连接 LMS 服务器</strong></summary>

**错误日志：**
```
Network check failed: 192.168.50.210:9000, error=...
```

**解决方案：**

```bash
# 1. 检查 LMS 服务器是否在线
ping 192.168.50.210
nc -zv 192.168.50.210 9000

# 2. 修改配置文件
nano ~/rpi-mediaplayer/oled_app/oled.ini

# 确认以下配置正确：
# [SERVER]
# HOST_IP = 192.168.50.210
# HOST_Port = 9000

# 3. 重启服务
systemctl --user restart oled
```

</details>

<details>
<summary><strong>错误 2：PLAYER_ID 未找到</strong></summary>

**错误日志：**
```
KeyError: 'PLAYER_ID'
```

**解决方案：**

```bash
# 1. 检查 oled.ini
cat ~/rpi-mediaplayer/oled_app/oled.ini | grep PLAYER_ID

# 2. 如果为空或错误，从 Squeezelite 日志获取 MAC 地址
journalctl --user -u squeezelite | grep -i mac

# 3. 手动编辑配置
nano ~/rpi-mediaplayer/oled_app/oled.ini

# 添加或修改:
# PLAYER_ID=02:xx:xx:xx:xx:xx  (使用实际的 MAC 地址)

# 4. 重启服务
systemctl --user restart oled
```

</details>

<details>
<summary><strong>错误 3：I2C 通信错误</strong></summary>

**错误日志：**
```
OSError: [Errno 121] Remote I/O error
```

**解决方案：**

```bash
# 方法 1: 降低 I2C 速度
sudo nano /boot/firmware/config.txt

# 修改 i2c-gpio 行，添加延迟参数
dtoverlay=i2c-gpio,bus=3,i2c_gpio_sda=4,i2c_gpio_scl=5,i2c_gpio_delay_us=2

# 方法 2: 检查接线
sudo i2cdetect -y 3

# 方法 3: 测试硬件
python3 /usr/local/bin/oled_display.py

# 重启系统
sudo reboot
```

</details>

<details>
<summary><strong>错误 4：字体文件缺失</strong></summary>

**错误日志：**
```
OSError: cannot open resource
```

**解决方案：**

```bash
# 1. 检查字体文件
ls -l ~/rpi-mediaplayer/oled_app/msyh.ttf

# 2. 如果不存在，从 resources 复制
sudo cp resources/oled/msyh.ttf ~/rpi-mediaplayer/oled_app/

# 3. 设置权限
sudo chown player:player ~/rpi-mediaplayer/oled_app/msyh.ttf

# 4. 重启服务
systemctl --user restart oled
```

</details>

<details>
<summary><strong>错误 5：Python 库版本问题</strong></summary>

```bash
# 激活虚拟环境
source ~/.venv/oled/bin/activate

# 检查已安装的库
pip list | grep luma

# 重新安装最新版本
pip install --upgrade luma.oled requests pillow

# 退出虚拟环境
deactivate

# 重启服务
systemctl --user restart oled
```

</details>

---

## 7. 蓝牙配对问题

### ❌ 配对后无法连接

**症状：**
- 蓝牙配对成功
- 但连接时显示"连接失败"

#### 🔍 高级排查

<details>
<summary><strong>方法 1：重置蓝牙协议栈</strong></summary>

```bash
# 1. 停止所有蓝牙服务
sudo systemctl stop bluetooth bluetooth-a2dp-autopair

# 2. 删除蓝牙缓存
sudo rm -rf /var/lib/bluetooth/*/*

# 3. 重启蓝牙
sudo systemctl restart bluetooth

# 4. 重新启动自动配对
sudo systemctl restart bluetooth-a2dp-autopair

# 5. 从手机端"忘记设备"后重新搜索
```

</details>

<details>
<summary><strong>方法 2：检查 PipeWire 蓝牙模块</strong></summary>

```bash
# 1. 列出已加载的模块
pactl list modules short | grep bluez

# 2. 重新加载蓝牙模块
pactl unload-module module-bluez5-device
pactl load-module module-bluez5-device

# 3. 重启 WirePlumber
systemctl --user restart wireplumber

# 4. 检查蓝牙 sink
pactl list sinks short | grep bluez
```

</details>

<details>
<summary><strong>方法 3：检查蓝牙配置文件</strong></summary>

```bash
# 查看 main.conf
cat /etc/bluetooth/main.conf

# 关键配置检查：
# [General]
# Class = 0x240414          ← 音频设备类型
# AlwaysPairable = true     ← 始终可配对
# JustWorksRepairing = always ← 自动重新配对

# 查看 WirePlumber 蓝牙配置
cat ~/.config/wireplumber/wireplumber.conf.d/51-bluetooth-fix.conf

# 重启相关服务
sudo systemctl restart bluetooth
systemctl --user restart pipewire wireplumber
```

</details>

**📖 详细蓝牙配对策略：** [`documents/BLUETOOTH_TIPS.md`](documents/BLUETOOTH_TIPS.md)

### 🔊 蓝牙音量控制说明
# 🔵 蓝牙音量控制说明

## 📊 蓝牙 A2DP 音量范围

### 技术规格

根据蓝牙 A2DP（Advanced Audio Distribution Profile）协议规范：

| 参数 | 值 | 说明 |
|------|---|------|
| **最小音量** | 0 | 静音 |
| **最大音量** | 127 | 蓝牙协议定义的最大值 |
| **数据类型** | `uint16` | 16位无符号整数 |
| **传输方式** | D-Bus | 通过 `org.bluez.MediaTransport1` 接口 |

### 🔄 音量映射关系

系统中的音量转换：

```
蓝牙原始值 (0-127) → 百分比 (0-100%)

转换公式：
percentage = (bt_value / 127) × 100
```

**示例：**
```python
BT_VOLUME_MAX = 127  # 蓝牙协议最大值

# 蓝牙音量 64 转换为百分比
bt_value = 64
percentage = int((bt_value / BT_VOLUME_MAX) * 100)  # = 50%

# 百分比 75% 转换为蓝牙音量
percentage = 75
bt_value = int((percentage / 100) * BT_VOLUME_MAX)  # = 95
```

---

## 🔧 音量控制实现

### Python 代码位置

**文件**: `resources/oled/query.py`

```python
# 行 20
BT_VOLUME_MAX = 127  # Bluetooth A2DP volume range: 0-127

def get_bluetooth_volume_dbus():
    """获取蓝牙音量（0-100%）"""
    # ... D-Bus 查询代码 ...
    
    # 转换为百分比
    return int((raw_value / BT_VOLUME_MAX) * 100)
```

---

## 🐛 常见问题

### ❌ 问题 1：音量显示不准确

**症状：**
- OLED 显示的音量与实际不符
- 音量跳跃或卡在某个值

**原因：**
- D-Bus 查询失败
- 蓝牙设备未正确连接

**解决方案：**

```bash
# 1. 检查蓝牙连接
bluetoothctl info <MAC地址>

# 2. 查看 D-Bus 音量接口
dbus-send --system --print-reply \
    --dest=org.bluez \
    /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX/fd1 \
    org.freedesktop.DBus.Properties.Get \
    string:org.bluez.MediaTransport1 \
    string:Volume

# 3. 重启 OLED 服务
systemctl --user restart oled
```

---

### ❌ 问题 2：音量调节无响应

**症状：**
- 手机调节音量，树莓派无反应
- OLED 音量条不更新

**原因：**
- PipeWire 蓝牙模块未加载
- 音量事件未传递

**解决方案：**

```bash
# 1. 检查 PipeWire 蓝牙模块
pactl list modules | grep bluez

# 2. 重新加载模块
pactl unload-module module-bluez5-device
pactl load-module module-bluez5-device

# 3. 重启 WirePlumber
systemctl --user restart wireplumber

# 4. 查看音量同步状态
pactl list sinks | grep -A 10 bluez
```

---

## 📚 参考资料

### 官方规范

- [Bluetooth A2DP Specification v1.3](https://www.bluetooth.com/specifications/specs/a2dp-1-3/)
- [BlueZ D-Bus API](https://git.kernel.org/pub/scm/bluetooth/bluez.git/tree/doc/media-api.txt)

### 相关代码

| 文件 | 行号 | 功能 |
|------|------|------|
| `resources/oled/query.py` | 20 | 定义 `BT_VOLUME_MAX = 127` |
| `resources/oled/query.py` | 233-256 | 实现 `get_bluetooth_volume_dbus()` |
| `resources/oled/state_handlers.py` | 43-75 | 处理蓝牙音量显示逻辑 |

---

## 💡 扩展阅读

### 为什么是 127？

蓝牙 A2DP 协议使用 **7 位音量控制**（0-127），保留最高位用于其他标志：

```
音量字段（8 bits）:
┌─┬─┬─┬─┬─┬─┬─┬─┐
│R│ Volume (0-127)│
└─┴─┴─┴─┴─┴─┴─┴─┘
 ↑
 保留位
```

这种设计提供了 **128 个音量级别**，足够精细控制，同时保持协议简单。

---

---

## 8. 日志和调试

### 📊 系统日志查看

#### 用户服务日志

```bash
# 查看所有用户服务状态
systemctl --user status

# 单个服务日志（最近 50 行）
journalctl --user -u pipewire -n 50
journalctl --user -u squeezelite -n 50
journalctl --user -u shairport-sync -n 50
journalctl --user -u oled -n 50
journalctl --user -u volume -n 50

# 实时日志（跟踪）
journalctl --user -u oled -f

# 查看错误日志
journalctl --user -u squeezelite -p err

# 查看特定时间段日志
journalctl --user -u oled --since "1 hour ago"
journalctl --user -u oled --since "2024-01-01 10:00:00"
```

#### 系统服务日志

```bash
# 系统蓝牙服务
journalctl -u bluetooth -n 50
journalctl -u bluetooth-a2dp-autopair -n 50

# 实时日志
journalctl -u bluetooth-a2dp-autopair -f

# 查看启动日志
journalctl -b -u bluetooth
```

#### 安装日志

```bash
# 查看安装日志
cat ~/installer/install.log

# 搜索错误
grep -i error ~/installer/install.log
grep -i failed ~/installer/install.log
```

---

### 🔧 调试工具

#### 音频调试

```bash
# 1. PipeWire 诊断
pw-dump  # 显示完整的 PipeWire 图

# 2. 查看音频流
pactl list sink-inputs

# 3. 查看所有 sink
pactl list sinks

# 4. ALSA 信息
aplay -L  # 列出所有播放设备
aplay -l  # 列出硬件设备
amixer -c 0 contents  # 显示所有控制

# 5. 测试音频延迟
pactl stat | grep -i latency
```

#### 硬件调试

```bash
# I2C 调试
sudo i2cdetect -y 1  # WM8960
sudo i2cdetect -y 3  # OLED

# GPIO 状态
gpio readall

# 内核消息
dmesg | tail -50
dmesg | grep -i error
dmesg | grep -i wm8960
dmesg | grep -i i2c

# USB 设备
lsusb

# PCI 设备
lspci
```

#### 网络调试

```bash
# 检查端口监听
sudo netstat -tuln | grep -E "5000|3483|9000"

# 查看网络连接
ss -tuln

# 测试端口连接
nc -zv 192.168.50.210 9000

# 查看路由表
ip route

# 查看 DNS
cat /etc/resolv.conf
```

---

### 🆘 紧急恢复

#### 服务完全重置

```bash
# 1. 停止所有服务
systemctl --user stop pipewire squeezelite shairport-sync oled volume
sudo systemctl stop bluetooth bluetooth-a2dp-autopair

# 2. 清除配置
rm -rf ~/.local/state/pipewire/
rm -rf ~/.config/pipewire/
rm -rf ~/.config/systemd/user/

# 3. 清除蓝牙缓存
sudo rm -rf /var/lib/bluetooth/*/*

# 4. 重启系统
sudo reboot

# 5. 重新部署
cd ~/installer
sudo ./stage_2.sh
```

#### 从头重新安装

```bash
# 在本地电脑上
cd RPI-MediaPlayer
./setup.sh

# 这将重新执行完整的两阶段安装
```

---

### 📞 获取帮助

如果以上方法都无法解决问题，请：

1. **📸 收集诊断信息：**
   ```bash
   # 生成诊断报告
   {
     echo "=== 系统信息 ==="
     uname -a
     cat /etc/os-release
     
     echo "=== 服务状态 ==="
     systemctl --user status pipewire squeezelite shairport-sync oled
     systemctl status bluetooth bluetooth-a2dp-autopair
     
     echo "=== 硬件信息 ==="
     aplay -l
     i2cdetect -y 1
     i2cdetect -y 3
     
     echo "=== 最近日志 ==="
     journalctl --user -u oled -n 20
     journalctl -u bluetooth -n 20
   } > ~/diagnostic_report.txt
   
   # 下载报告到本地
   scp -i ./rpi_keys/id_rpi player@rpi.local:~/diagnostic_report.txt ./
   ```

2. **🐛 提交 Issue：**
   - 前往 [GitHub Issues](https://github.com/yourusername/RPI-MediaPlayer/issues)
   - 附上诊断报告
   - 描述具体问题和重现步骤

3. **💬 社区讨论：**
   - [GitHub Discussions](https://github.com/yourusername/RPI-MediaPlayer/discussions)
   - 分享经验和解决方案

---

<div align="center">

**🎯 问题解决了？太好了！**

如果本指南帮助了您，请考虑给项目 ⭐ Star

</div>
