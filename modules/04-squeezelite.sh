#!/usr/bin/env bash
# modules/04-squeezelite.sh (重构版 - 修复环境变量污染)
set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"

log "安装 Squeezelite (LMS 播放器)..."

# ============================================
# 1. 读取配置
# ============================================
log "1/6. 读取 Squeezelite 配置..."
PLAYER_NAME=$(config_require "squeezelite" "name")
SERVER_IP=$(config_require "squeezelite" "server")
ALSA_DEVICE=$(config_get_or_default "squeezelite" "device" "default")
EXTRA_ARGS=$(config_get_or_default "squeezelite" "args" "")

log " 播放器名称: $PLAYER_NAME"
log " LMS 服务器: $SERVER_IP"
log " ALSA 设备: $ALSA_DEVICE"

# ============================================
# 2. 生成 MAC 地址
# ============================================
log "2/6. 生成虚拟 MAC 地址..."
generate_random_mac() {
    printf '02:%02x:%02x:%02x:%02x:%02x' \
        $(od -An -N1 -tu1 /dev/urandom | awk '{print $1}') \
        $(od -An -N1 -tu1 /dev/urandom | awk '{print $1}') \
        $(od -An -N1 -tu1 /dev/urandom | awk '{print $1}') \
        $(od -An -N1 -tu1 /dev/urandom | awk '{print $1}') \
        $(od -An -N1 -tu1 /dev/urandom | awk '{print $1}')
}

PLAYER_MAC=$(generate_random_mac)

# 验证 MAC 地址格式
if ! echo "$PLAYER_MAC" | grep -Eq '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
    error "MAC 地址格式无效: $PLAYER_MAC"
fi

# ✅ 修复：使用命名空间前缀导出
export RPI_PLAYER_MAC="$PLAYER_MAC"

log " 生成的 MAC 地址: $PLAYER_MAC"

# ============================================
# 3. 安装软件包
# ============================================
log "3/6. 安装 Squeezelite 软件包..."
install_pkg squeezelite

SQUEEZE_VERSION=$(squeezelite -? 2>&1 | head -1 || echo "未知版本")
log " 版本: $SQUEEZE_VERSION"

# ============================================
# 4. 禁用系统服务
# ============================================
log "4/6. 禁用系统级 Squeezelite 服务..."
if systemctl list-unit-files | grep -q "squeezelite.service"; then
    sudo systemctl disable squeezelite --now 2>/dev/null || true
    sudo systemctl mask squeezelite 2>/dev/null || true
    log " ✓ 系统服务已禁用"
else
    log " 系统服务不存在（跳过）"
fi

# ============================================
# 5. 安装启动脚本和服务
# ============================================
log "5/6. 安装启动脚本和用户服务..."

# 5.1 安装启动脚本（使用局部变量，无需改动）
install_template_script "squeezelite.sh" "squeezelite.sh" \
    "PIPEWIRE_TIMEOUT=$PIPEWIRE_READY_TIMEOUT" \
    "PLAYER_NAME=$PLAYER_NAME" \
    "SERVER_IP=$SERVER_IP" \
    "PLAYER_MAC=$PLAYER_MAC" \
    "ALSA_DEVICE=$ALSA_DEVICE" \
    "EXTRA_ARGS=$EXTRA_ARGS"

log " ✓ 启动脚本已安装: $SYSTEM_BIN_DIR/squeezelite.sh"

# 5.2 安装用户服务
install_template_service "squeezelite.service" "squeezelite.service" "true" \
    "SYSTEM_BIN_DIR=$SYSTEM_BIN_DIR"

log " ✓ 用户服务已安装: squeezelite.service"

# ============================================
# 6. 启动并验证服务
# ============================================
log "6/6. 启动 Squeezelite 服务..."

enable_user_service squeezelite.service
start_user_service squeezelite.service
wait_for_service squeezelite.service user 10

SERVICE_STATUS=$(check_service_status squeezelite.service user)

if [[ "$SERVICE_STATUS" == "active" ]] || [[ "$SERVICE_STATUS" == "activating" ]]; then
    log "✓ Squeezelite 运行中"
    log " 播放器 ID: $PLAYER_MAC"
    log " LMS 服务器: $SERVER_IP"
else
    warn "Squeezelite 服务状态: $SERVICE_STATUS"
    warn "参阅 TROUBLESHOOTING.md 获取帮助"
fi

log "✓ Squeezelite 安装完成"
