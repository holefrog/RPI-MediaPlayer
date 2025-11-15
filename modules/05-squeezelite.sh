#!/usr/bin/env bash
# 注意：此模块由 stage_2.sh 通过 source 调用，环境已初始化
set -euo pipefail

log "安装 Squeezelite..."

# ============================================
# 1. 安装软件包
# ============================================
log "1/5. 安装 squeezelite..."
install_pkg squeezelite

log "✓ Squeezelite 版本:"
squeezelite -t 2>&1 | head -1 | sed 's/^/  /' || echo "  (版本信息获取失败)"

# ============================================
# 2. 读取配置
# ============================================
log "2/5. 读取配置..."

PLAYER_NAME=$(config_require "squeezelite" "name")
SERVER_IP=$(config_require "squeezelite" "server")
PLAYER_MAC=$(config_require "squeezelite" "mac")
ALSA_DEVICE=$(config_get_or_default "squeezelite" "device" "default")
EXTRA_ARGS=$(config_get_or_default "squeezelite" "args" "")

log "  播放器名称: $PLAYER_NAME"
log "  LMS 服务器: $SERVER_IP"
log "  MAC 地址: $PLAYER_MAC"
log "  ALSA 设备: $ALSA_DEVICE"
[[ -n "$EXTRA_ARGS" ]] && log "  额外参数: $EXTRA_ARGS"

# ============================================
# 3. 验证配置
# ============================================
log "3/5. 验证配置..."

# 验证 MAC 地址格式
if ! echo "$PLAYER_MAC" | grep -Eq '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
    error "MAC 地址格式错误: $PLAYER_MAC
正确格式: xx:xx:xx:xx:xx:xx (例如: dc:a6:32:40:b5:ff)"
fi

log "✓ 配置验证通过"

# ============================================
# 4. 安装启动脚本
# ============================================
log "4/5. 从模板安装 squeezelite.sh 启动脚本..."

install_template_script "squeezelite.sh" "squeezelite.sh" \
    "PIPEWIRE_TIMEOUT=$PIPEWIRE_READY_TIMEOUT" \
    "PLAYER_NAME=$PLAYER_NAME" \
    "SERVER_IP=$SERVER_IP" \
    "PLAYER_MAC=$PLAYER_MAC" \
    "ALSA_DEVICE=$ALSA_DEVICE" \
    "EXTRA_ARGS=$EXTRA_ARGS"

# ============================================
# 5. 安装并启动用户服务
# ============================================
log "5/5. 从模板安装 squeezelite.service 用户服务..."

install_template_service \
    "squeezelite.service" \
    "squeezelite.service" \
    "true" \
    "SYSTEM_BIN_DIR=$SYSTEM_BIN_DIR"

enable_user_service squeezelite.service
start_user_service squeezelite.service

# 等待服务启动
sleep 2

# 验证服务状态
if user_service_status squeezelite.service | grep -q "active"; then
    log "✓ Squeezelite 安装完成并运行中"
else
    warn "Squeezelite 服务可能未正常启动
请检查: systemctl --user status squeezelite
日志: journalctl --user -u squeezelite -f"
fi

log "  配置信息:"
log "    播放器: $PLAYER_NAME"
log "    服务器: $SERVER_IP"
log "    MAC: $PLAYER_MAC"

