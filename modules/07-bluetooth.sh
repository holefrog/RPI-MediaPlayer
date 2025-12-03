#!/usr/bin/env bash
# modules/07-bluetooth.sh - 蓝牙音频服务（修复版 - 配置化超时）
# 注意：此模块由 stage_2.sh 通过 source 调用，环境已初始化
set -euo pipefail

# 定义模块名称（日志前缀）
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"

log "安装蓝牙音频..."

# ============================================
# 0. 读取配置
# ============================================
BT_NAME=$(config_require "bluetooth" "name")
CHECK_INTERVAL=$(config_get_or_default "bluetooth" "check_interval" "20")

# 🆕 读取超时配置
BT_INIT_DELAY=$(config_get_or_default "timeouts" "bt_init_delay" "2")
BT_RFKILL_DELAY=$(config_get_or_default "timeouts" "bt_rfkill_delay" "2")

log " 蓝牙设备名称: $BT_NAME"
log " 检查间隔: ${CHECK_INTERVAL}秒"
log " 初始化延迟: ${BT_INIT_DELAY}秒"
log " Rfkill 延迟: ${BT_RFKILL_DELAY}秒"

# ============================================
# 1. 安装软件包
# ============================================
log "1/5. 安装蓝牙软件包..."
install_pkg bluez bluez-tools pulseaudio-module-bluetooth

# ============================================
# 2. 系统蓝牙配置
# ============================================
log "2/5. 配置系统蓝牙..."

BT_MAIN_CONF="/etc/bluetooth/main.conf"
if [[ -f "$BT_MAIN_CONF" ]] && [[ ! -f "${BT_MAIN_CONF}.bak" ]]; then
    sudo cp "$BT_MAIN_CONF" "${BT_MAIN_CONF}.bak"
fi

install_template_file \
    "${TEMPLATES_CONFIGS_DIR}/bluetooth-main.conf.template" \
    "$BT_MAIN_CONF" \
    "BT_NAME=$BT_NAME"

log "✓ 系统蓝牙配置已更新"

# ============================================
# 3. WirePlumber 蓝牙增强配置
# ============================================
log "3/5. 配置 WirePlumber 蓝牙路由..."

WIREPLUMBER_BT_CONF="${USER_HOME}/.config/wireplumber/wireplumber.conf.d/51-bluetooth-fix.conf"
# 使用 run_as_user 创建目录
run_as_user mkdir -p "$(dirname "$WIREPLUMBER_BT_CONF")"

install_template_file \
    "${TEMPLATES_CONFIGS_DIR}/wireplumber-bluetooth.conf.template" \
    "$WIREPLUMBER_BT_CONF"

sudo chown "$USER_NAME:$USER_NAME" "$WIREPLUMBER_BT_CONF"
log "✓ WirePlumber 蓝牙配置已安装"

# ============================================
# 4. 重启蓝牙系统服务
# ============================================
log "4/5. 重启蓝牙系统服务..."

# 🆕 使用配置化延迟
sudo rfkill unblock bluetooth
sleep "$BT_RFKILL_DELAY"

enable_system_service bluetooth
start_system_service bluetooth
wait_for_service bluetooth system 10

SERVICE_STATUS=$(check_service_status bluetooth system)
if [[ "$SERVICE_STATUS" == "active" ]] || [[ "$SERVICE_STATUS" == "activating" ]]; then
    log "✓ 系统蓝牙服务运行中"
    log " 重启 PipeWire 以应用蓝牙配置..."
else
    error "蓝牙服务启动失败（状态: $SERVICE_STATUS）。"
fi

# 使用 run_as_user 重启用户服务
run_as_user systemctl --user restart pipewire pipewire-pulse wireplumber
wait_for_pipewire

log "✓ PipeWire 已重启并应用蓝牙配置"

# ============================================
# 5. 安装蓝牙自动配对服务
# ============================================
log "5/5. 安装蓝牙自动配对服务..."

BT_CONFIG_DIR=$(get_bt_config_dir)
PINS_FILE="$BT_CONFIG_DIR/pins.txt"

# 使用 run_as_user 创建目录
run_as_user mkdir -p "$BT_CONFIG_DIR"

# 创建 PIN 码文件
echo "* *" | sudo tee "$PINS_FILE" >/dev/null
sudo chown "$USER_NAME:$USER_NAME" "$PINS_FILE"
sudo chmod 600 "$PINS_FILE"

log " ✓ PIN 配置文件已创建"

# 🆕 传递超时配置到模板
install_template_script \
    "bluetooth-a2dp-autopair.sh" \
    "bluetooth-a2dp-autopair.sh" \
    "BT_NAME=$BT_NAME" \
    "USER_NAME=$USER_NAME" \
    "PINS_FILE=$PINS_FILE" \
    "USER_RUNTIME_DIR=$USER_RUNTIME_DIR" \
    "CHECK_INTERVAL=$CHECK_INTERVAL" \
    "BT_INIT_DELAY=$BT_INIT_DELAY" \
    "BT_RFKILL_DELAY=$BT_RFKILL_DELAY"

install_template_service \
    "bluetooth-a2dp-autopair.service" \
    "bluetooth-a2dp-autopair.service" \
    "false" \
    "SYSTEM_BIN_DIR=$SYSTEM_BIN_DIR" \
    "USER_NAME=$USER_NAME" \
    "USER_ID=$USER_ID" \
    "USER_RUNTIME_DIR=$USER_RUNTIME_DIR"

enable_system_service bluetooth-a2dp-autopair
start_system_service bluetooth-a2dp-autopair
wait_for_service bluetooth-a2dp-autopair system 10

SERVICE_STATUS=$(check_service_status bluetooth-a2dp-autopair system)
if [[ "$SERVICE_STATUS" == "active" ]] || [[ "$SERVICE_STATUS" == "activating" ]]; then
    log "✓ 蓝牙自动配对服务运行中"
else
    error "蓝牙自动配对服务状态: $SERVICE_STATUS"
fi

log "✓ 蓝牙音频安装完成"
