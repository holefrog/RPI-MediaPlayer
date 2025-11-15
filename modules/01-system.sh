#!/usr/bin/env bash
# modules/01-system.sh - 系统基础配置（第 1 阶段）
# 注意：此模块由 stage_1.sh 通过 source 调用，环境已初始化

set -euo pipefail

# ============================================
# 文件操作
# ============================================
append_config() {
    local file="$1"
    local line="$2"

    # 构造用于 grep 的正则：行首可选空格，然后紧跟要添加的内容
    local pattern="^[[:space:]]*${line//\//\\/}"

    # 如果未找到未被注释的相同行，则添加
    if ! grep -qE "$pattern" "$file" 2>/dev/null; then
        echo "$line" | sudo tee -a "$file" >/dev/null
        log "  添加配置: $line → $file"
    fi
}

log "开始系统基础配置..."

# ============================================
# 1. 读取配置
# ============================================
log "1/8. 读取系统配置..."
TIMEZONE=$(config_get_or_default "system" "timezone" "UTC")
AUTO_UPDATE=$(config_get_or_default "system" "auto_update" "no")
DEVICE_HOSTNAME=$(config_require "device" "hostname")

# ============================================
# 2. 设置时区和本地化（修复顺序）
# ============================================
log "2/8. 设置时区和本地化..."
if [[ -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
    sudo timedatectl set-timezone "$TIMEZONE"
else
    warn "无效的时区: $TIMEZONE，跳过设置"
fi

# 确保 locale 文件存在
if [[ ! -f /etc/locale.gen ]]; then
    sudo touch /etc/locale.gen
fi

# 启用 en_GB.UTF-8（如果未启用）
if ! grep -q "^en_GB.UTF-8 UTF-8" /etc/locale.gen; then
    echo "en_GB.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen >/dev/null
    log "  已启用 en_GB.UTF-8 locale"
fi

# 生成 locale（在设置之前）
log "  正在生成 locale..."
if ! sudo locale-gen en_GB.UTF-8 2>&1 | grep -q "done"; then
    warn "locale 生成可能失败，但将继续..."
fi

# 更新系统 locale 配置
sudo update-locale LANG=en_GB.UTF-8 LANGUAGE=en_GB:en LC_ALL=en_GB.UTF-8

# 仅在当前 shell 中设置（避免错误）
export LANG=en_GB.UTF-8
export LANGUAGE=en_GB:en
export LC_ALL=en_GB.UTF-8

log "✓ locale 配置完成（将在重启后完全生效）"

# ============================================
# 3. 设置主机名
# ============================================
log "3/8. 设置主机名..."
if [[ "$(hostname)" != "$DEVICE_HOSTNAME" ]]; then
    log "设置主机名: $DEVICE_HOSTNAME"
    echo "$DEVICE_HOSTNAME" | sudo tee /etc/hostname >/dev/null
    sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$DEVICE_HOSTNAME/" /etc/hosts
    sudo hostname "$DEVICE_HOSTNAME" || warn "hostname 命令执行失败（将在重启后生效）"
fi

# ============================================
# 4. 配置 .bashrc (原步骤 8)
# ============================================
readonly bashrc="$USER_HOME/.bashrc"
readonly alias_line="alias ll='ls -l'"
log "4/8. 配置用户 $bashrc..."
append_config "$bashrc" "$alias_line"


# ============================================
# 5. 系统更新 (原步骤 4)
# ============================================
log "5/8. 处理系统更新..."
if [[ "$AUTO_UPDATE" == "yes" ]]; then
    log "正在更新系统软件包..."
    sudo apt-get update
    sudo apt-get upgrade -y
    log "✓ 系统更新完成"
else
    log "跳过系统更新（auto_update=no）"
fi

# ============================================
# 6. 启用 SSH 和 Linger (原步骤 5)
# ============================================
log "6/8. 启用 SSH 和用户 Linger..."
sudo systemctl enable ssh --now
enable_linger

# ============================================
# 7. 安装硬件依赖 (原步骤 6)
# ============================================
log "7/8. 安装硬件依赖包..."
install_pkg i2c-tools alsa-utils libasound2t64

# ============================================
# 8. 配置硬件（/boot/config.txt）(★ 已修改)
# ============================================
log "8/8. 配置 /boot/firmware/config.txt..."
[[ -f "$BOOT_CONFIG" ]] || error "引导配置文件不存在: $BOOT_CONFIG"

log "  ... 启用 I2C"
sudo modprobe i2c_dev || true
append_config /etc/modules "i2c_dev"
append_config "$BOOT_CONFIG" "dtparam=i2c_arm=on"

if module_enabled "audio"; then
    log "  ... 配置 WM8960 音频驱动"
    append_config "$BOOT_CONFIG" "dtparam=i2s=on"
    append_config "$BOOT_CONFIG" "dtparam=audio=off"
    append_config "$BOOT_CONFIG" "dtoverlay=wm8960-soundcard"
    append_config "$BOOT_CONFIG" "dtoverlay=i2s-mmap"
fi

# (★ 已修改: 动态读取 SDA/SCL 引脚)
if module_enabled "oled"; then
    OLED_BUS=$(config_get_or_default "oled" "bus" "1")
    if [[ "$OLED_BUS" == "3" ]]; then
        log "  ... 配置 GPIO 模拟 I2C-3 (OLED)"
        
        # 从 config.ini 读取 SDA 和 SCL 引脚配置，提供默认值
        OLED_SDA=$(config_get_or_default "oled" "i2c_gpio_sda" "4")
        OLED_SCL=$(config_get_or_default "oled" "i2c_gpio_scl" "5")
        
        # 使用变量构建配置行
        readonly i2c_overlay="dtoverlay=i2c-gpio,bus=3,i2c_gpio_sda=${OLED_SDA},i2c_gpio_scl=${OLED_SCL}"
        
        log "    使用引脚: SDA=$OLED_SDA, SCL=$OLED_SCL"
        append_config "$BOOT_CONFIG" "$i2c_overlay"
    fi
fi

log "✓ 系统基础配置完成"
