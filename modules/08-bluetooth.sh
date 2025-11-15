#!/usr/bin/env bash
# modules/08-bluetooth.sh - 蓝牙音频（最终修复版：图标和音量控制）
# 注意：此模块由 stage_2.sh 通过 source 调用，环境已初始化
set -euo pipefail

# 修复：确保 SCRIPT_DIR 已定义 (它应该由 stage_2.sh 定义)
if [ -z "${SCRIPT_DIR:-}" ]; then
    # SCRIPT_DIR 未定义，自动检测 (假设此脚本在 .../modules/ 目录中)
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
    log "WARN: SCRIPT_DIR 未由 stage_2.sh 定义, 自动设置为: $SCRIPT_DIR"
fi

log "安装蓝牙音频..."

# ============================================
# 1. 读取配置
# ============================================
log "1/8. 读取配置..."

BT_NAME=$(config_require "bluetooth" "name")
AUTO_CONNECT=$(config_get_or_default "bluetooth" "auto_connect" "yes")

log "  蓝牙名称: $BT_NAME"
log "  自动连接: $AUTO_CONNECT"

# ============================================
# 2. 安装软件包
# ============================================
log "2/8. 安装蓝牙软件包..."

install_pkg bluez bluez-tools pulseaudio-module-bluetooth

log "✓ 蓝牙软件包安装完成"

# ============================================
# 3. 配置蓝牙主配置文件（修复安卓和 Apple 兼容性）
# ============================================
log "3/8. 配置蓝牙主配置文件..."

BT_MAIN_CONF="/etc/bluetooth/main.conf"

# 备份原配置
if [[ -f "$BT_MAIN_CONF" ]] && [[ ! -f "${BT_MAIN_CONF}.bak" ]]; then
    sudo cp "$BT_MAIN_CONF" "${BT_MAIN_CONF}.bak"
    log "  已备份: ${BT_MAIN_CONF}.bak"
fi

# 创建优化的蓝牙配置
cat <<EOF | sudo tee "$BT_MAIN_CONF" >/dev/null
[General]
Name = $BT_NAME

# 关键：设置设备类型为 "Speaker" (0x240414)
Class = 0x240414

DiscoverableTimeout = 0
PairableTimeout = 0
AlwaysPairable = true
JustWorksRepairing = always

# 针对 Apple 设备的稳定性修复
FastConnectable = false
Privacy = device
IdleTimeout = 0

ControllerMode = dual
Experimental = true

[Policy]
AutoEnable = true
ReconnectAttempts = 7
ReconnectIntervals = 1,2,4,8,16,32,64
EOF

log "✓ 蓝牙主配置已更新: $BT_MAIN_CONF"

# ============================================
# 4. 配置 WirePlumber 蓝牙音频路由 (🔥 最终修复)
# ============================================
log "4/8. 配置 WirePlumber 蓝牙音频路由 (修复音量控制)..."

WIREPLUMBER_BT_CONF="${USER_HOME}/.config/wireplumber/wireplumber.conf.d/51-bluetooth-fix.conf"

# 创建配置目录
sudo -u "$USER_NAME" mkdir -p "$(dirname "$WIREPLUMBER_BT_CONF")"

# 创建蓝牙音频路由配置
cat <<'EOF' | sudo tee "$WIREPLUMBER_BT_CONF" >/dev/null
# WirePlumber 蓝牙音频路由修复配置
monitor.bluez.properties = {
  # 🔥 关键修复 (1/2)：恢复完整的 hw-volume 列表
  # 这允许手机正确协商音量控制，修复“调整音量即出错”的问题
  bluez5.hw-volume = [ hfp_hf hsp_hs a2dp_sink hfp_ag hsp_ag a2dp_source ]
  
  # 🔥 关键修复 (2/2)：只启用 A2DP Sink (扬声器) 角色
  # 这能确保手机将其识别为纯扬声器，而不是耳麦（修复图标问题）
  bluez5.roles = [ a2dp_sink ]
  
  # 启用所有编解码器
  bluez5.codecs = [ sbc sbc_xq aac ldac aptx aptx_hd aptx_ll faststream ]
  
  bluez5.enable-sbc-xq = true
  bluez5.enable-msbc = true
  bluez5.enable-hw-volume = true
}
monitor.bluez.rules = [
  {
    matches = [ { device.name = "~bluez_card.*" } ]
    actions = {
      update-props = {
        bluez5.auto-connect = [ a2dp_sink ]
        # 确保规则也只关注 a2dp_sink
        bluez5.hw-volume = [ a2dp_sink ]
        device.profile = "a2dp-sink"
        priority.driver = 1000
        priority.session = 1000
        node.pause-on-idle = false
        session.suspend-timeout-seconds = 0
      }
    }
  }
]
EOF

sudo chown "$USER_NAME:$USER_NAME" "$WIREPLUMBER_BT_CONF"
log "✓ WirePlumber 蓝牙配置已创建: $WIREPLUMBER_BT_CONF"

# ============================================
# 5. 清理旧配对信息
# ============================================
log "5/8. 清理旧配对信息..."

BT_DEVICES_DIR="/var/lib/bluetooth"

if [[ -d "$BT_DEVICES_DIR" ]]; then
    log "  清理 $BT_DEVICES_DIR 中的旧设备信息..."
    sudo find "$BT_DEVICES_DIR" -type f -name "cache" -delete 2>/dev/null || true
    sudo find "$BT_DEVICES_DIR" -type d -name "[0-9A-F][0-9A-F]:*" -exec rm -rf {} + 2>/dev/null || true
    log "✓ 旧配对信息已清理"
else
    log "  跳过清理（目录不存在）"
fi

# ============================================
# 6. 启用蓝牙服务
# ============================================
log "6/8. 启用蓝牙服务..."

sudo systemctl enable bluetooth --now

# 等待蓝牙服务启动
sleep 3

if ! systemctl is-active bluetooth >/dev/null 2>&1; then
    error "蓝牙服务启动失败
请检查: systemctl status bluetooth"
fi

log "✓ 蓝牙服务已启动"

# ============================================
# 7. 重启 PipeWire 和 WirePlumber（应用新配置）
# ============================================
log "7/8. 重启 PipeWire 和 WirePlumber..."

sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    systemctl --user stop pipewire pipewire-pulse wireplumber 2>/dev/null || true
sleep 2
sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    systemctl --user restart pipewire pipewire-pulse wireplumber

wait_for_pipewire
log "✓ PipeWire 和 WirePlumber 已重启"

# ============================================
# 8. 安装蓝牙自动配对与路由服务 (已合并)
# ============================================
log "8/8. 安装蓝牙自动配对与音频路由服务..."

# 创建脚本 (使用修改后的模板)
readonly bt_autopair_script_tpl="${SCRIPT_DIR}/templates/scripts/bluetooth-a2dp-autopair.sh.template"
readonly bt_autopair_script="/usr/local/bin/bluetooth-a2dp-autopair.sh"
fill_template "$bt_autopair_script_tpl" "$bt_autopair_script"
sudo chmod 755 "$bt_autopair_script"

# 创建服务 (使用修改后的模板)
readonly bt_autopair_service_tpl="${SCRIPT_DIR}/templates/services/bluetooth-a2dp-autopair.service.template"
readonly bt_autopair_service="/etc/systemd/system/bluetooth-a2dp-autopair.service"
fill_template "$bt_autopair_service_tpl" "$bt_autopair_service"

sudo systemctl daemon-reload
sudo systemctl enable bluetooth-a2dp-autopair.service --now

if ! systemctl is-active bluetooth-a2dp-autopair >/dev/null 2>&1; then
    warn "蓝牙自动配对服务启动失败"
    warn "请检查: systemctl status bluetooth-a2dp-autopair"
    warn "或日志: journalctl -u bluetooth-a2dp-autopair -f"
else
    log "✓ 蓝牙自动配对与音频路由服务已启动"
fi


# ============================================
# 完成
# ============================================
log "✓ 蓝牙音频安装完成"
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  蓝牙配置信息 (已集成音频路由)"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""
log "📱 设备名称: $BT_NAME"
log "🔈 设备类型: Speaker (纯 A2DP Sink)"
log ""
log "🔧 配对说明:"
log "  1. 在手机/电脑上搜索蓝牙设备"
log "  2. 选择 '$BT_NAME'"
log "  3. 系统会自动接受配对（无需 PIN）"
Note
log "  4. 连接成功后音频会自动路由到 WM8960"
log ""
log "🔊 音量层级（已优化）:"
log "  - WM8960 硬件: 90% (固定)"
log "  - PipeWire Sink: 60% (初始)"
log "  - 蓝牙软件音量: 由手机控制"
log ""
log "⚙️  配置文件:"
log "  - /etc/bluetooth/main.conf"
log "  - ~/.config/wireplumber/wireplumber.conf.d/51-bluetooth-fix.conf"
log ""
log "🛠️  诊断工具 (已合并):"
log "  bluetooth-a2dp-autopair.sh diagnose    # 运行蓝牙音频诊断"
log ""
log "🔍 故障排查:"
log "  systemctl status bluetooth               # 查看蓝牙服务"
log "  systemctl status bluetooth-a2dp-autopair # 查看配对与路由服务"
log "  journalctl -u bluetooth-a2dp-autopair -f # 查看配对与路由日志"
log "  bluetooth-a2dp-autopair.sh diagnose      # 运行诊断"
log ""
log "💡 安卓设备无声时："
log "  1. 运行: bluetooth-a2dp-autopair.sh diagnose"
log "  2. 检查输出中的 '⚠️ 非默认设备' 提示"
log "  3. 手动设置: pactl set-default-sink <bluez_sink_name>"
log "  4. 或重启服务: systemctl restart bluetooth-a2dp-autopair"
log ""
log "🎯 自动修复功能:"
log "  - bluetooth-a2dp-autopair.service 会自动监控蓝牙连接"
log "  - 检测到新的蓝牙 sink 后自动配置音量和路由"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
