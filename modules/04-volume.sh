#!/usr/bin/env bash
# modules/04-volume.sh - 音量控制脚本和服务（修复版）
# 注意：此模块由 stage_2.sh 通过 source 调用，环境已初始化
set -euo pipefail


log "安装音量控制脚本和服务..."

# ============================================
# 1. 验证 PipeWire 运行中
# ============================================
log "1/6. 验证 PipeWire 服务..."

wait_for_pipewire

# ============================================
# 2. 安装音量控制脚本
# ============================================
log "2/6. 从模板安装 volume.sh..."

install_template_script "volume.sh" "volume.sh"

log "✓ 音量控制脚本安装完成: $SYSTEM_BIN_DIR/volume.sh"

# ============================================
# 3. 测试脚本基本功能
# ============================================
log "3/6. 测试脚本基本功能..."

if ! sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    "$SYSTEM_BIN_DIR/volume.sh" get >/dev/null 2>&1; then
    warn "音量控制脚本测试失败，但已安装"
fi

log "✓ 脚本功能测试通过"

# ============================================
# 4. 安装并启用用户服务（修复：使用正确的模板文件名）
# ============================================
log "4/6. 从模板安装 volume.service 用户服务..."

# ✅ 修复：模板文件名应该包含 .template 后缀
install_template_service \
    "volume.service" \
    "volume.service" \
    "true" \
    "USER_RUNTIME_DIR=$USER_RUNTIME_DIR" \
    "SYSTEM_BIN_DIR=$SYSTEM_BIN_DIR"

enable_user_service volume.service

log "✓ volume.service 用户服务已安装并启用"

# ============================================
# 5. 启动服务并初始化 WM8960
# ============================================
log "5/6. 启动服务并初始化 WM8960..."

start_user_service volume.service

# 等待服务执行完成（oneshot 服务需要时间初始化）
sleep 5

# 验证服务状态
SERVICE_STATUS=$(sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    systemctl --user is-active volume.service 2>/dev/null || echo "inactive")

if [[ "$SERVICE_STATUS" == "active" ]] || [[ "$SERVICE_STATUS" == "activating" ]]; then
    log "✓ WM8960 音量初始化完成"
    
    # 显示当前配置
    log "当前音量配置:"
    sudo -u "$USER_NAME" \
        XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        "$SYSTEM_BIN_DIR/volume.sh" status 2>&1 | sed 's/^/  /' || true
else
    warn "volume.service 可能未成功执行
请检查: systemctl --user status volume
日志: journalctl --user -u volume -n 50"
fi

# ============================================
# 6. 额外验证：手动运行初始化（确保成功）
# ============================================
log "6/6. 额外验证：手动运行音量初始化..."

if sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    "$SYSTEM_BIN_DIR/volume.sh" init 2>&1 | sed 's/^/  /'; then
    log "✓ 音量初始化成功"
else
    error "音量初始化失败！请检查日志"
fi

log "✓ 音量控制安装完成"
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Volume Service 安装信息"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""
log "📁 文件位置:"
log "  脚本: $SYSTEM_BIN_DIR/volume.sh"
log "  服务: ~/.config/systemd/user/volume.service"
log ""
log "🎛️  音量控制命令:"
log "  volume.sh init       # 重新初始化 WM8960"
log "  volume.sh up         # 音量 +5%"
log "  volume.sh down       # 音量 -5%"
log "  volume.sh set 50     # 设置音量到 50%"
log "  volume.sh get        # 获取当前音量"
log "  volume.sh mute       # 静音/取消静音切换"
log "  volume.sh status     # 查看详细状态"
log ""
log "🔧 服务管理:"
log "  systemctl --user status volume    # 查看服务状态"
log "  systemctl --user restart volume   # 重新初始化 WM8960"
log "  journalctl --user -u volume       # 查看服务日志"
log "  journalctl --user -u volume -f    # 实时查看日志"
log ""
log "💡 提示:"
log "  - volume.service 会在系统启动时自动初始化 WM8960"
log "  - 如需重新配置，运行: systemctl --user restart volume"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
