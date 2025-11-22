#!/usr/bin/env bash
# modules/06-airplay.sh (重构版)
# 注意：此模块由 stage_2.sh 通过 source 调用，环境已初始化

# 定义模块名称（日志前缀）
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"


set -euo pipefail

# 加载工具库（确保 log 等函数可用，兼容独立运行模式）
# 假设脚本位于 modules/ 目录，utils.sh 位于 lib/ 目录
if [[ -z "$(type -t log)" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/utils.sh"
fi

log "安装 AirPlay (Shairport-Sync)..."

# ============================================
# 1. 安装软件包
# ============================================
log "1/7. 安装 Shairport-Sync 软件包..."
install_pkg shairport-sync

log "✓ Shairport-Sync 版本:"
shairport-sync -V 2>&1 | head -1 | sed 's/^/  /' || echo "  (版本信息获取失败)"

# ============================================
# 2. 读取配置
# ============================================
log "2/7. 读取 AirPlay 配置..."
AIRPLAY_NAME=$(config_require "airplay" "name")
AIRPLAY_PORT=$(config_require "airplay" "port")
ALSA_DEVICE=$(config_get_or_default "airplay" "device" "default")
INITIAL_VOLUME=$(config_get_or_default "airplay" "initial_volume" "100")

log " AirPlay 名称: $AIRPLAY_NAME"
log " 监听端口: $AIRPLAY_PORT"
log " ALSA 设备: $ALSA_DEVICE"
log " 初始音量: $INITIAL_VOLUME%"

# ============================================
# 3. 验证配置
# ============================================
log "3/7. 验证配置参数..."

# 验证端口号
if ! [[ "$AIRPLAY_PORT" =~ ^[0-9]+$ ]] || \
   [[ "$AIRPLAY_PORT" -lt 1024 ]] || \
   [[ "$AIRPLAY_PORT" -gt 65535 ]]; then
    error "无效的端口号: $AIRPLAY_PORT (应为 1024-65535)"
fi

# 验证初始音量
if ! [[ "$INITIAL_VOLUME" =~ ^[0-9]+$ ]] || \
   [[ "$INITIAL_VOLUME" -lt 0 ]] || \
   [[ "$INITIAL_VOLUME" -gt 100 ]]; then
    error "无效的初始音量: $INITIAL_VOLUME (应为 0-100)"
fi

log "✓ 配置验证通过"

# ============================================
# 4. 创建 Metadata 管道（修复审核建议 #9 - 权限安全）
# ============================================
log "4/7. 配置 Metadata 管道..."

# 获取管道路径（优先使用 env.sh 中定义的函数，如果未定义则使用默认值）
if [[ "$(type -t get_metadata_pipe)" == "function" ]]; then
    METADATA_PIPE=$(get_metadata_pipe)
else
    METADATA_PIPE="/tmp/shairport-sync-metadata"
    log " (使用默认管道路径: $METADATA_PIPE)"
fi

log " 管道路径: $METADATA_PIPE"

# 删除旧管道（如果存在）
if [[ -e "$METADATA_PIPE" ]]; then
    log " 删除旧的 metadata 管道..."
    sudo rm -f "$METADATA_PIPE"
fi

# 创建新的命名管道
if ! sudo mkfifo "$METADATA_PIPE"; then
    error "无法创建 metadata 管道: $METADATA_PIPE"
fi

# 设置权限（修复审核建议 #9：使用 664 而非 666）
sudo chown "$USER_NAME:$USER_NAME" "$METADATA_PIPE"
sudo chmod 664 "$METADATA_PIPE"

log "✓ Metadata 管道已创建"
log " 权限: $(ls -l "$METADATA_PIPE" | awk '{print $1, $3, $4}')"

# ============================================
# 5. 生成配置文件
# ============================================
log "5/7. 生成 Shairport-Sync 配置..."

SHAIRPORT_CONF_DIR="/etc/shairport-sync"
sudo mkdir -p "$SHAIRPORT_CONF_DIR"

# 使用模板生成配置文件
install_template_file \
    "${TEMPLATES_CONFIGS_DIR}/shairport-sync.conf.template" \
    "$SHAIRPORT_CONF_DIR/shairport-sync.conf" \
    "AIRPLAY_NAME=$AIRPLAY_NAME" \
    "AIRPLAY_PORT=$AIRPLAY_PORT" \
    "ALSA_DEVICE=$ALSA_DEVICE" \
    "INITIAL_VOLUME=$INITIAL_VOLUME" \
    "METADATA_PIPE=$METADATA_PIPE"

sudo chmod 644 "$SHAIRPORT_CONF_DIR/shairport-sync.conf"

log "✓ 配置文件已生成: $SHAIRPORT_CONF_DIR/shairport-sync.conf"
log " Metadata 管道: $METADATA_PIPE"

# ============================================
# 6. 禁用系统服务
# ============================================
log "6/7. 禁用系统级 Shairport-Sync 服务..."
if systemctl list-unit-files | grep -q "shairport-sync.service"; then
    sudo systemctl disable shairport-sync --now 2>/dev/null || true
    sudo systemctl mask shairport-sync 2>/dev/null || true
    log " ✓ 系统服务已禁用"
else
    log " 系统服务不存在（跳过）"
fi

# ============================================
# 7. 安装并启动用户服务（使用统一函数）
# ============================================
log "7/7. 安装并启动 Shairport-Sync 服务..."

install_template_service "shairport-sync.service" "shairport-sync.service" "true"

enable_user_service shairport-sync.service
start_user_service shairport-sync.service

# 使用统一的等待函数
wait_for_service shairport-sync.service user 10

# 验证服务状态（统一风格）
SERVICE_STATUS=$(check_service_status shairport-sync.service user)

if [[ "$SERVICE_STATUS" == "active" ]] || [[ "$SERVICE_STATUS" == "activating" ]]; then
    log "✓ Shairport-Sync 运行中"
else
    warn "参阅 TROUBLESHOOTING.md 获取帮助"
    error "Shairport-Sync 服务状态: $SERVICE_STATUS"
fi

# ============================================
# 8. 音量初始化 + Metadata 管道验证
# ============================================
log "初始化 AirPlay 音量设置并验证 metadata..."

# 等待 PipeWire 就绪
wait_for_pipewire

# 从配置读取 PipeWire sink 默认音量
DEFAULT_SINK_VOLUME=$(config_get_or_default "audio" "default_sink_volume" "100")

# 设置 PipeWire sink 音量
log " 设置 PipeWire sink 音量为 ${DEFAULT_SINK_VOLUME}%..."
if sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    pactl set-sink-volume @DEFAULT_SINK@ "${DEFAULT_SINK_VOLUME}%"; then
    log " ✓ PipeWire sink 音量已设置为 ${DEFAULT_SINK_VOLUME}%"
else
    warn "无法设置 PipeWire sink 音量"
fi

# 验证 metadata 管道
log " 验证 metadata 管道状态..."
if [[ -p "$METADATA_PIPE" ]]; then
    log " ✓ Metadata 管道类型正确（FIFO）"
    
    # 检查管道是否可读
    if [[ -r "$METADATA_PIPE" ]]; then
        log " ✓ Metadata 管道可读"
    else
        warn "Metadata 管道不可读，请检查权限"
    fi
else
    error "Metadata 管道创建失败或类型错误: $METADATA_PIPE"
fi

log "✓ AirPlay 音量初始化和 metadata 管道配置完成"
