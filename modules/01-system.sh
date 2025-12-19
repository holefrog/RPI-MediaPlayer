#!/usr/bin/env bash
# modules/01-system.sh - 系统基础配置（第 1 阶段）
# 注意：此模块由 stage_1.sh 通过 source 调用，环境已初始化


set -euo pipefail

# 定义模块名称（日志前缀）
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"

# 加载工具库（此时会使用上面定义的 SCRIPT_NAME）
# 假设当前脚本在 modules/ 目录下，utils.sh 在 lib/ 目录下
source "$(dirname "${BASH_SOURCE[0]}")/../lib/utils.sh"

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
        log " 添加配置: $line → $file"
    fi
}

log "开始系统基础配置..."

# ============================================
# 1. 读取配置
# ============================================
log "1/7. 读取系统配置..."
TIMEZONE=$(config_get_or_default "system" "timezone" "UTC")
AUTO_UPDATE=$(config_get_or_default "system" "auto_update" "no")

# ============================================
# 2. 设置时区和本地化（修复顺序）
# ============================================
log "2/7. 设置时区和本地化..."
if [[ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
    warn "无效的时区: $TIMEZONE，跳过设置"
else
    sudo timedatectl set-timezone "$TIMEZONE"
fi


# 确保 locale 文件存在
# 如果 BOOT_CONFIG 存在且 /etc/locale.gen 不存在，则创建它
if [ -f "$BOOT_CONFIG" ] && [ ! -f /etc/locale.gen ]; then
    sudo touch /etc/locale.gen
fi

# 启用 en_GB.UTF-8（如果未启用）
if ! grep -q "^en_GB.UTF-8 UTF-8" /etc/locale.gen; then
    echo "en_GB.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen >/dev/null
    log " 已启用 en_GB.UTF-8 locale"
fi

# 生成 locale（在设置之前）
log " 正在生成 locale..."
if ! sudo locale-gen en_GB.UTF-8 2>&1 | tee -a "$INSTALL_LOG"; then
    error "locale 生成失败！这会导致中文显示问题，请检查系统配置。"
fi


# 更新系统 locale 配置
sudo update-locale LANG=en_GB.UTF-8 LANGUAGE=en_GB:en LC_ALL=en_GB.UTF-8

# 仅在当前 shell 中设置（避免错误）
export LANG=en_GB.UTF-8
export LANGUAGE=en_GB:en
export LC_ALL=en_GB.UTF-8

log "✓ locale 配置完成（将在重启后完全生效）"


# ============================================
# 3. 配置 .bashrc
# ============================================
readonly bashrc="$USER_HOME/.bashrc"
readonly alias_line="alias ll='ls -l'"
log "3/7. 配置用户 $bashrc..."
append_config "$bashrc" "$alias_line"

# ============================================
# 4. 系统更新
# ============================================
log "4/7. 处理系统更新..."
if [ -f "$BOOT_CONFIG" ] && [ "$AUTO_UPDATE" = "yes" ]; then
    log "正在更新系统软件包..."
    sudo apt-get update
    sudo apt-get upgrade -y
    log "✓ 系统更新完成"
else
    log "跳过系统更新（auto_update=no）"
fi

# ============================================
# 5. 启用 SSH 和 Linger
# ============================================
log "5/7. 启用 用户 Linger..."
enable_linger

# ============================================
# 6. 安装硬件依赖
# ============================================
log "6/7. 安装硬件依赖包..."
install_pkg i2c-tools alsa-utils libasound2t64 dbus-user-session

# ============================================
# 7. 配置硬件（/boot/config.txt）
# ============================================
log "7/7. 配置 /boot/firmware/config.txt..."
[ -f "$BOOT_CONFIG" ] || error "引导配置文件不存在: $BOOT_CONFIG"

log " ... 启用 I2C"
sudo modprobe i2c_dev || true
append_config /etc/modules "i2c_dev"
append_config "$BOOT_CONFIG" "dtparam=i2c_arm=on"

log " ... 配置 WM8960 音频驱动"
append_config "$BOOT_CONFIG" "dtparam=i2s=on"
append_config "$BOOT_CONFIG" "dtparam=audio=off"
append_config "$BOOT_CONFIG" "dtoverlay=wm8960-soundcard"
append_config "$BOOT_CONFIG" "dtoverlay=i2s-mmap"

log " ... 配置 OLED"
OLED_BUS=$(config_require "oled" "bus")
OLED_SDA=$(config_require "oled" "sda_pin")
OLED_SCL=$(config_require "oled" "scl_pin")

log " ... 配置 GPIO(OLED): SDA=${OLED_SDA}, SCL=${OLED_SCL}"
append_config "$BOOT_CONFIG" "dtoverlay=i2c-gpio,bus=${OLED_BUS},i2c_gpio_sda=${OLED_SDA},i2c_gpio_scl=${OLED_SCL}"

log "✓ 系统基础配置完成"
