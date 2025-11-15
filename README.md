# 🎵 RPI MediaPlayer

Turn your **Raspberry Pi** into a versatile **multi-source media player** that supports **LMS**, **AirPlay**, **Bluetooth audio**, and **OLED display** — all in one device.

---

## 🧩 Hardware

- **Raspberry Pi 4B (4GB)**
- **Waveshare WM8960 Sound Card**
- **SSD1306 OLED Display (128x64)** (optional)

---

## 💽 Operating System

- **Raspberry Pi OS Trixie 64-bit**

---

## 🎯 Purpose

Transform your Raspberry Pi into a powerful home media player capable of:

- **Squeezelite Player** – Play music from **Logitech Media Server (LMS)**
- **AirPlay Sink** – Receive and play audio from **Apple devices**
- **Bluetooth Speaker** – Stream audio from **Bluetooth devices**
- **OLED Display** – Show real-time playback info, artist, and track details

---

## ✨ Features

- 🚀 **Two-stage installation** with automatic reboot handling
- 🖥️ **OLED display** shows current track and playback info (using Luma library)
- 🔄 **Multi-source audio** support (LMS / AirPlay / Bluetooth)
- 🧠 **Clean modular scripts** for easy customization
- 🛡️ **Strict error handling** - installation stops on any error
- 📋 **Comprehensive verification** - validate installation success
- 🔍 **Dependency checking** - validates module dependencies before install
- 📦 **Resource management** - organized resource files for extensions

---

## ⚙️ Installation

### Prerequisites

1. **Raspberry Pi** with Raspberry Pi OS Trixie 64-bit installed
2. **SSH access** configured on your Raspberry Pi
3. **SSH key pair** for passwordless authentication

### Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/RPI-MediaPlayer.git
cd RPI-MediaPlayer

# 2. Create SSH key (if not exists)
ssh-keygen -t ed25519 -f ./rpi_keys/id_rpi -C "player@rpi"

# ⚠️ IMPORTANT: Never commit private keys to Git!
# The .gitignore file is configured to prevent this.

# 3. Copy public key to Raspberry Pi
ssh-copy-id -i ./rpi_keys/id_rpi.pub player@rpi.local

# 4. Edit configuration
nano config.ini
# Update these settings:
#   [ssh] host, user
#   [device] name, hostname
#   [squeezelite] name, server, mac
#   [airplay] name
#   [bluetooth] name
#   [oled] bus, address

# 5. Run setup script (First time)
./setup.sh

# ⚠️ STAGE 1: System Configuration
# The script will configure:
#   - System basics (timezone, hostname, locale)
#   - I2C modules
#   - Audio driver (WM8960)
#   - OLED I2C GPIO
# 
# After Stage 1, you MUST reboot!

# 6. Reboot the system
# ssh -i ./rpi_keys/id_rpi player@rpi.local 'sudo reboot'
# Wait 30-60 seconds for reboot to complete

# 7. Run setup script again (Second time)
./setup.sh

# ⚠️ STAGE 2: Service Installation
# The script will install and configure:
#   - PipeWire audio service
#   - Volume control
#   - Squeezelite player
#   - OLED display program
#   - AirPlay receiver
#   - Bluetooth audio

# 8. Verify installation
ssh -i ./rpi_keys/id_rpi player@rpi.local
cd /tmp/rpi-mediaplayer
./verify.sh
```

---

## 🔄 Two-Stage Installation Process

### Why Two Stages?

Hardware configurations (audio driver, I2C GPIO) require kernel module loading, which **only takes effect after a reboot**. To ensure reliability:

1. **Stage 1** configures hardware and system basics
2. **Reboot** to apply kernel changes
3. **Stage 2** installs and configures services

### Stage 1: System Configuration

Handled by `01-system.sh`:
- ✅ Timezone and locale
- ✅ Hostname
- ✅ SSH service
- ✅ User session persistence (linger)
- ✅ **I2C module** (`i2c_dev`)
- ✅ **WM8960 audio driver** (dtoverlay)
- ✅ **OLED I2C GPIO** (dtoverlay for I2C-3)

**After Stage 1**: The script will automatically detect the need to reboot and prompt you.

### Stage 2: Service Installation

Handled by remaining modules:
- ✅ `02-audio.sh` - Verify audio driver (no config changes)
- ✅ `03-pipewire.sh` - PipeWire audio service
- ✅ `04-volume.sh` - Volume control script
- ✅ `05-squeezelite.sh` - Squeezelite player
- ✅ `06-oled.sh` - OLED display program (no config changes)
- ✅ `07-airplay.sh` - AirPlay receiver
- ✅ `08-bluetooth.sh` - Bluetooth audio

**After Stage 2**: All services are running and ready to use!

---

## 🔒 Security Notes

### SSH Key Management

⚠️ **CRITICAL**: Never commit SSH private keys to version control!

- The `.gitignore` file is pre-configured to exclude all keys
- Private key file: `rpi_keys/id_rpi` (excluded from Git)
- Public key file: `rpi_keys/id_rpi.pub` (excluded from Git)
- Always verify your `.gitignore` is working: `git status`

### If You Accidentally Committed Keys

If you've already committed private keys to Git:

```bash
# 1. Remove keys from Git history (use git-filter-repo or BFG)
# DO NOT just delete and commit - history still contains them!

# 2. Generate new keys immediately
rm -f ./rpi_keys/id_rpi*
ssh-keygen -t ed25519 -f ./rpi_keys/id_rpi -C "player@rpi"

# 3. Copy new public key to Raspberry Pi
ssh-copy-id -i ./rpi_keys/id_rpi.pub player@rpi.local

# 4. Update remote repository
git push --force
```

---

## 📁 Project Structure

```
RPI-MediaPlayer/
├── .gitignore              # Git ignore rules (protects sensitive files)
├── config.ini              # ⭐ Main configuration file
├── setup.sh                # Local deployment script
├── install.sh              # Remote installation script (two-stage)
├── verify.sh               # Installation verification script
├── login.sh                # Quick SSH login helper
├── README.md               # This file
│
├── lib/
│   └── utils.sh            # Common utility functions
│
├── modules/                # Installation modules (sequential)
│   ├── 01-system.sh        # ⭐ STAGE 1: System + hardware config
│   ├── 02-audio.sh         # STAGE 2: Audio driver verification
│   ├── 03-pipewire.sh      # STAGE 2: PipeWire audio service
│   ├── 04-volume.sh        # STAGE 2: Volume control
│   ├── 05-squeezelite.sh   # STAGE 2: Squeezelite player
│   ├── 06-oled.sh          # STAGE 2: OLED display program
│   ├── 07-airplay.sh       # STAGE 2: AirPlay receiver
│   └── 08-bluetooth.sh     # STAGE 2: Bluetooth audio
│
├── resources/              # 🎁 Resource files
│   └── oled/               # OLED display program
│       ├── config.ini      # LMS server configuration
│       ├── config.py       # Configuration loader
│       ├── display.py      # Display control
│       ├── main.py         # Main program
│       ├── query.py        # LMS query module
│       ├── msyh.ttf        # Chinese font (optional)
│       └── oled_luma.py    # Test script (optional)
│
└── rpi_keys/               # SSH keys directory (git-ignored)
    ├── id_rpi              # SSH private key (DO NOT COMMIT!)
    └── id_rpi.pub          # SSH public key (DO NOT COMMIT!)
```

---

## 🔧 Configuration

All settings are in `config.ini`. Key sections:

### SSH Connection (Required)
```ini
[ssh]
host=rpi.local          # Raspberry Pi hostname or IP
user=player             # SSH username
port=22                 # SSH port
key=./rpi_keys/id_rpi   # SSH private key path
```

### Module Switches

⚠️ **Important**: Module dependencies are validated before installation

```ini
[modules]
system=yes      # System configuration (REQUIRED - Stage 1)
audio=yes       # WM8960 driver (Stage 1 config, Stage 2 verify)
pipewire=yes    # PipeWire (REQUIRED for squeezelite/airplay/volume)
volume=yes      # Volume control script (requires pipewire)
squeezelite=yes # LMS player (requires pipewire)
oled=yes        # OLED display (Stage 1 I2C config, Stage 2 install)
airplay=yes     # AirPlay receiver (requires pipewire)
bluetooth=yes   # Bluetooth audio
```

**Dependency Rules:**
- `system` → **REQUIRED** (always enabled)
- `squeezelite`, `airplay`, `volume` → **require** `pipewire=yes`
- `pipewire` → **recommends** `audio=yes`
- `oled` → **requires** I2C (configured in Stage 1)

### OLED Display (if enabled)
```ini
[oled]
type=ssd1306      # Display type (ssd1306 only)
bus=3             # I2C bus number (1 or 3)
address=0x3C      # I2C address (0x3C or 0x3D)
width=128         # Display width (pixels)
height=64         # Display height (pixels)
```

**After installation, configure LMS server:**
```bash
# Edit OLED configuration on Raspberry Pi
ssh -i ./rpi_keys/id_rpi player@rpi.local
nano ~/rpi-mediaplayer/oled_app/config.ini

# Update:
[SERVER]
HOST_IP = 192.168.50.210    # Your LMS server IP
HOST_Port = 9000             # Your LMS CLI port

# Restart service
systemctl --user restart oled.service
```

---

## 🔍 Troubleshooting

### Installation Requires Two Runs

**Behavior**: After first `./setup.sh`, the script prompts you to reboot and run again.

**Explanation**: This is **normal and expected**!
- Stage 1 configures hardware (needs reboot)
- Stage 2 installs services (after reboot)

**Solution**: Follow the prompts:
```bash
# First run
./setup.sh
# → Reboot prompt

# Reboot
ssh -i ./rpi_keys/id_rpi player@rpi.local 'sudo reboot'

# Wait 30-60 seconds

# Second run
./setup.sh
# → Installation complete!
```

### Audio Not Working

1. **Check sound card**:
   ```bash
   aplay -l
   ```
   Should show `wm8960-soundcard`. If not, you need to complete **Stage 1** and reboot.

2. **Check PipeWire**:
   ```bash
   systemctl --user status pipewire pipewire-pulse
   ```

### OLED Not Displaying

1. **Check I2C device**:
   ```bash
   ls /dev/i2c-*
   i2cdetect -y 3  # or i2cdetect -y 1
   ```
   If device missing, you need to complete **Stage 1** and reboot.

2. **Check service status**:
   ```bash
   systemctl --user status oled.service
   journalctl --user -u oled.service -f
   ```

---

## 📝 Changelog

### v1.3.0 (Current - Two-Stage Installation)

**🏗️ Architecture Changes:**
1. **Two-stage installation process** for reliability
2. Consolidated hardware configuration into `01-system.sh`
3. Separated verification from configuration

**🎯 Stage 1 (System Configuration):**
4. All dtoverlay configurations in one place
5. I2C module setup for audio and OLED
6. Automatic reboot detection and prompting

**🎯 Stage 2 (Service Installation):**
7. `02-audio.sh` now only verifies (no config changes)
8. `06-oled.sh` now only installs software (no config changes)
9. All service installations after hardware is ready

**✨ Benefits:**
10. More reliable installation (hardware ready before services)
11. Clearer error messages (hardware vs service issues)
12. Better user experience (explicit two-stage process)

---

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly (both stages!)
5. **DO NOT commit SSH keys or sensitive data**
6. Update documentation
7. Submit a pull request

**Adding new modules?** 
- Stage 1 modules: Modify `01-system.sh` for hardware/kernel config
- Stage 2 modules: Create new `0X-name.sh` for service installation

---

## ⚠️ Important Notes

1. **Two-Stage Installation**: First run configures hardware, second run installs services
2. **Reboot Required**: After Stage 1, reboot is mandatory
3. **Unique MAC**: Each Squeezelite instance needs a unique MAC address
4. **Network**: All services require stable network connection
5. **User Services**: Most services run as user-level (systemctl --user)

---

Enjoy your RPI MediaPlayer! 🎵 🖥️
