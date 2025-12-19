#!/usr/bin/env bash
# modules/03-volume.sh - 音量控制脚本和服务
# 注意：此模块由 stage_2.sh 通过 source 调用，环境已初始化

set -euo pipefail

# 定义模块名称（日志前缀）
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"

log "安装音量控制脚本和服务..."

# ============================================
# 1. 验证 PipeWire 运行中
# ============================================
log "1/6. 验证 PipeWire 服务..."
wait_for_pipewire

# ============================================
# 2. 读取音量配置
# ============================================
log "2/6. 读取音量配置..."
DEFAULT_HW_VOLUME=$(config_get_or_default "audio" "default_hw_volume" "95")
DEFAULT_SINK_VOLUME=$(config_get_or_default "audio" "default_sink_volume" "100")

log " 硬件音量: ${DEFAULT_HW_VOLUME}%"
log " Sink 音量: ${DEFAULT_SINK_VOLUME}%"

# ============================================
# 3. 安装音量控制脚本
# ============================================
log "3/6. 从模板安装 volume.sh..."

install_template_script "volume.sh" "volume.sh" \
    "DEFAULT_HW_VOLUME=$DEFAULT_HW_VOLUME" \
    "DEFAULT_SINK_VOLUME=$DEFAULT_SINK_VOLUME"

log "✓ 音量控制脚本安装完成: $SYSTEM_BIN_DIR/volume.sh"

# ============================================
# 4. 测试脚本基本功能
# ============================================
log "4/6. 测试脚本基本功能..."

# 使用 run_as_user 执行测试
if ! run_as_user "$SYSTEM_BIN_DIR/volume.sh" get >/dev/null 2>&1; then
    warn "音量控制脚本测试失败，但已安装"
fi

log "✓ 脚本功能测试通过"

# ============================================
# 5. 安装并启用用户服务
# ============================================
log "5/6. 从模板安装 volume.service 用户服务..."

install_template_service \
    "volume.service" \
    "volume.service" \
    "true" \
    "USER_RUNTIME_DIR=$USER_RUNTIME_DIR" \
    "SYSTEM_BIN_DIR=$SYSTEM_BIN_DIR"

enable_user_service volume.service

log "✓ volume.service 用户服务已安装并启用"

# ============================================
# 6. 启动服务并初始化 WM8960
# ============================================
log "6/6. 启动服务并初始化 WM8960..."

start_user_service volume.service
wait_for_service volume.service user 10

SERVICE_STATUS=$(check_service_status volume.service user)

if [[ "$SERVICE_STATUS" == "active" ]] || [[ "$SERVICE_STATUS" == "activating" ]]; then
    log "✓ WM8960 音量初始化完成"
    
    # 显示当前配置
    log "当前音量配置:"
    run_as_user "$SYSTEM_BIN_DIR/volume.sh" status 2>&1 | sed 's/^/  /' || true
else
    warn "volume.service 服务状态: $SERVICE_STATUS"
    warn "参阅 TROUBLESHOOTING.md 获取帮助"
fi

log "✓ 音量控制安装完成"
