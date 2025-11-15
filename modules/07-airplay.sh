#!/usr/bin/env bash
# modules/07-airplay.sh (修复版) - AirPlay音量优化
# 注意:此模块由 stage_2.sh 通过 source 调用,环境已初始化
set -euo pipefail

log "安装 AirPlay (Shairport-Sync)..."

# ============================================
# 1. 安装软件包
# ============================================
log "1/6. 安装 shairport-sync..."
install_pkg shairport-sync

log "✓ Shairport-Sync 版本:"
shairport-sync -V 2>&1 | head -1 | sed 's/^/  /' || echo "  (版本信息获取失败)"

# ============================================
# 2. 读取配置
# ============================================
log "2/6. 读取配置..."

AIRPLAY_NAME=$(config_require "airplay" "name")
AIRPLAY_PORT=$(config_require "airplay" "port")
ALSA_DEVICE=$(config_get_or_default "airplay" "device" "default")

# 新增:读取初始音量配置(默认100%)
INITIAL_VOLUME=$(config_get_or_default "airplay" "initial_volume" "100")

log "  AirPlay 名称: $AIRPLAY_NAME"
log "  监听端口: $AIRPLAY_PORT"
log "  ALSA 设备: $ALSA_DEVICE"
log "  初始音量: $INITIAL_VOLUME%"

# ============================================
# 3. 验证配置
# ============================================
log "3/6. 验证配置..."

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
# 4. 创建配置文件 (优化版)
# ============================================
log "4/6. 创建 shairport-sync 配置文件..."

sudo mkdir -p /etc/shairport-sync

CONFIG_CONTENT=$(cat <<EOF
general = {
    name = "$AIRPLAY_NAME";
    port = $AIRPLAY_PORT;
    interpolation = "soxr";
    output_backend = "alsa";
};

alsa = {
    output_device = "$ALSA_DEVICE";
    
    // 关键: 不使用硬件mixer控制
    // 让PipeWire统一管理音量
    mixer_control_name = "None";
};

metadata = {
    enabled = "yes";
    include_cover_art = "yes";
};

// 关键: 音量控制优化
volume = {
    // 设置初始音量为100%(或配置值)
    initial_volume = $INITIAL_VOLUME;
    
    // 音量范围: -30dB 到 0dB (软件音量)
    range_db = 30;
    
    // 启用音量控制(允许iOS设备调节)
    control = "yes";
};

EOF
)

echo "$CONFIG_CONTENT" | sudo tee /etc/shairport-sync/shairport-sync.conf >/dev/null
sudo chmod 644 /etc/shairport-sync/shairport-sync.conf

log "✓ 配置文件已创建: /etc/shairport-sync/shairport-sync.conf"

# 禁用系统服务(我们使用用户服务)
sudo systemctl disable shairport-sync --now 2>/dev/null || true
sudo systemctl mask shairport-sync 2>/dev/null || true

# ============================================
# 5. 安装并启动用户服务
# ============================================
log "5/6. 从模板安装 shairport-sync.service 用户服务..."

install_template_service \
    "shairport-sync.service" \
    "shairport-sync.service" \
    "true"

enable_user_service shairport-sync.service
start_user_service shairport-sync.service

# 等待服务启动
sleep 2

# 验证服务状态
if user_service_status shairport-sync.service | grep -q "active"; then
    log "✓ AirPlay 安装完成并运行中"
else
    warn "AirPlay 服务可能未正常启动
请检查: systemctl --user status shairport-sync
日志: journalctl --user -u shairport-sync -f"
fi

# ============================================
# 6. 音量初始化 (新增)
# ============================================
log "6/6. 初始化AirPlay音量设置..."

# 等待PipeWire就绪
wait_for_pipewire

# 确保PipeWire sink音量为100%
log "  设置PipeWire sink音量为100%..."
if ! sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    pactl set-sink-volume @DEFAULT_SINK@ 100%; then
    warn "无法设置PipeWire sink音量"
else
    log "  ✓ PipeWire sink音量已设置为100%"
fi

log "✓ AirPlay音量初始化完成"
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  AirPlay 安装信息"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""
log "📱 连接方法:"
log "  1. 在Apple设备上打开控制中心"
log "  2. 点击AirPlay图标"
log "  3. 选择 '$AIRPLAY_NAME'"
log ""
log "🔊 音量说明:"
log "  - 初始音量: $INITIAL_VOLUME%"
log "  - 硬件音量(WM8960): 100% (固定)"
log "  - PipeWire音量: 100% (固定)"
log "  - AirPlay软件音量: $INITIAL_VOLUME% (可通过iOS调节)"
log ""
log "⚙️  配置文件:"
log "  /etc/shairport-sync/shairport-sync.conf"
log ""
log "🔧 服务管理:"
log "  systemctl --user status shairport-sync"
log "  journalctl --user -u shairport-sync -f"
log ""
log "💡 如需调整初始音量:"
log "  1. 编辑 config.ini: [airplay] initial_volume=80"
log "  2. 重新运行: ./setup.sh"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
