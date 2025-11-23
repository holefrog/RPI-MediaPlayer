#!/usr/bin/env bash
# stage_2.sh - RPI MediaPlayer 安装 - 第 2 阶段（完整版 - 增强服务状态检查）
set -euo pipefail

# 定义模块名称（日志前缀）
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"

cd "$(dirname "$0")"

# ============================================
# 辅助函数
# ============================================
verify_i2c_device() {
    local bus="${1:-1}"
    local addr="${2:-}"
    local dev="/dev/i2c-${bus}"
    
    [[ -e "$dev" ]] || return 1
    command -v i2cdetect &>/dev/null || return 1
    
    if [[ -n "$addr" ]]; then
        local addr_hex="${addr#0x}"
        if i2cdetect -y "$bus" 2>/dev/null | grep -iq "$addr_hex"; then
            return 0
        else
            return 2
        fi
    fi
    return 0
}

# ============================================
# 🆕 增强的服务状态检查函数
# ============================================
check_and_report_service() {
    local svc_name="$1"
    local svc_type="${2:-user}"
    local status
    
    if [[ "$svc_type" == "user" ]]; then
        status=$(run_as_user systemctl --user is-active "$svc_name" 2>/dev/null || echo "unknown")
    else
        status=$(systemctl is-active "$svc_name" 2>/dev/null || echo "unknown")
    fi
    
    local svc_display=$(printf "%-24s" "$svc_name")
    
    case "$status" in
        active)
            log "✓ ${svc_display} [${svc_type}]  active"
            return 0
            ;;
        activating)
            warn "⏳ ${svc_display} [${svc_type}]  activating (启动中)"
            return 1
            ;;
        failed)
            warn "✗ ${svc_display} [${svc_type}]  FAILED"
            if [[ "$svc_type" == "user" ]]; then
                warn "   → 查看日志: journalctl --user -u $svc_name -n 20"
            else
                warn "   → 查看日志: journalctl -u $svc_name -n 20"
            fi
            return 2
            ;;
        inactive|dead)
            warn "○ ${svc_display} [${svc_type}]  inactive (未启动)"
            return 1
            ;;
        *)
            warn "? ${svc_display} [${svc_type}]  unknown"
            return 1
            ;;
    esac
}

# ============================================
# 1. 初始化
# ============================================
[[ -f "lib/utils.sh" ]] || exit 1
source lib/utils.sh
init_install_env

exec > >(tee -a "$INSTALL_LOG")
exec 2>&1

log "=========================================="
log "RPI MediaPlayer 安装程序"
log ">>> 第 2 阶段：服务安装"
log "=========================================="
log "日志文件: $INSTALL_LOG"
log ""

# ============================================
# 2. 硬件验证
# ============================================
log "正在验证硬件..."
hardware_check_failed=false

# 2.1 WM8960
log "检查 WM8960 声卡..."
WM8960_BUS=$(config_get_or_default "wm8960" "bus" "1")
log "检查 WM8960 声卡 (I2C-$WM8960_BUS)..."
if ! verify_i2c_device "$WM8960_BUS"; then
    error "I2C-$WM8960_BUS 验证失败！请参阅 documents/HW_WM8960.md。"
fi

if ! aplay -l 2>/dev/null | grep -q "wm8960"; then
    error "WM8960 声卡未检测到！请参阅 documents/HW_WM8960.md。"
fi

log "✓ WM8960 验证通过"

# 2.2 OLED
log "检查 OLED 显示屏..."

OLED_BUS=$(config_get_or_default "oled" "bus" "3")
OLED_ADDR=$(config_require "oled" "address")

if ! verify_i2c_device "$OLED_BUS"; then
    warn "I2C-$OLED_BUS 未找到，跳过 OLED 安装。"
    hardware_check_failed=true
else
    log "I2C-$OLED_BUS 总线已就绪"
    
    # 验证设备地址
    verify_i2c_device "$OLED_BUS" "$OLED_ADDR" || true
    verify_result=$?
    
    if [[ $verify_result -eq 0 ]]; then
        log "✓ OLED 设备已检测到: $OLED_ADDR"
    elif [[ $verify_result -eq 2 ]]; then
        warn "OLED 设备 ($OLED_ADDR) 未在 I2C-$OLED_BUS 上检测到"
        warn "请运行: i2cdetect -y $OLED_BUS 检查实际地址"
        hardware_check_failed=true
    else
        warn "OLED 设备验证失败（未知错误）"
        hardware_check_failed=true
    fi
fi

if [[ "$hardware_check_failed" == true ]]; then
    error "硬件验证失败。请参阅 documents/TROUBLESHOOTING.md 和 documents/HW_SSD1306.md。"
fi

log "✓ 硬件验证完成"
log ""

# ============================================
# 3. 执行模块
# ============================================
log "=========================================="
log "开始安装服务模块..."
log "=========================================="
log ""

for module_file in modules/*.sh; do
    module_name=$(basename "$module_file" .sh | cut -d'-' -f2)
    [[ "$module_name" == "system" ]] && continue
    
    log ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    log ">>> 安装模块: $module_name"
    log ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    log ""
    
    if ! source "$module_file" 2>&1; then
        error "模块 $module_name 安装失败"
    fi
    
    log ""
    log "✓ 模块 $module_name 完成"
    log ""
done

# ============================================
# 4. 清理系统
# ============================================
log "=========================================="
log "清理系统..."
log "=========================================="
sudo apt-get autoremove -y

log ""
log "✓ 系统清理完成"
log ""

# ============================================
# 🆕 5. 增强的最终服务状态检查
# ============================================
log "=========================================="
log ">>> 最终服务状态检查"
log "=========================================="
log ""

# 检查用户服务
log "用户服务状态:"
user_services_failed=0
user_services_activating=0

for svc in pipewire squeezelite oled shairport-sync volume wireplumber; do
    if ! check_and_report_service "${svc}.service" "user"; then
        exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            ((user_services_failed++))
        elif [[ $exit_code -eq 1 ]]; then
            ((user_services_activating++))
        fi
    fi
done

log ""

# 检查系统服务
log "系统服务状态:"
system_services_failed=0
system_services_activating=0

for svc in bluetooth bluetooth-a2dp-autopair; do
    if ! check_and_report_service "${svc}.service" "system"; then
        exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            ((system_services_failed++))
        elif [[ $exit_code -eq 1 ]]; then
            ((system_services_activating++))
        fi
    fi
done

log ""

# ============================================
# 6. 服务状态汇总报告
# ============================================
total_failed=$((user_services_failed + system_services_failed))
total_activating=$((user_services_activating + system_services_activating))

log "=========================================="
log "服务状态汇总"
log "=========================================="
log "用户服务:"
log "  - 失败: $user_services_failed"
log "  - 启动中: $user_services_activating"
log ""
log "系统服务:"
log "  - 失败: $system_services_failed"
log "  - 启动中: $system_services_activating"
log ""

if [[ $total_failed -gt 0 ]]; then
    warn "=========================================="
    warn "⚠️  发现 $total_failed 个服务启动失败"
    warn "=========================================="
    warn ""
    warn "建议操作："
    warn "1. 重启系统后再次检查: sudo reboot"
    warn "2. 查看失败服务的日志（参见上方提示）"
    warn "3. 参阅 documents/TROUBLESHOOTING.md 获取详细排查指南"
    warn ""
elif [[ $total_activating -gt 0 ]]; then
    warn "=========================================="
    warn "⏳ $total_activating 个服务仍在启动中"
    warn "=========================================="
    warn ""
    warn "这是正常现象，服务将在几秒内完全启动"
    warn "重启后所有服务将自动就绪"
    warn ""
else
    log "=========================================="
    log "✅ 所有服务状态正常"
    log "=========================================="
    log ""
fi

# ============================================
# 7. 完成
# ============================================
log "=========================================="
log "✓ RPI MediaPlayer 安装完成！"
log "=========================================="
log ""
log "📌 重要提示："
log "1. 系统将执行最终重启以确保所有服务完全就绪"
log "2. 如有服务未运行，将在重启后自动启动"
log "3. 重启后使用以下命令查看服务状态："
log ""
log "   用户服务:"
log "   systemctl --user status pipewire"
log "   systemctl --user status squeezelite"
log "   systemctl --user status oled"
log "   systemctl --user status shairport-sync"
log ""
log "   系统服务:"
log "   systemctl status bluetooth"
log "   systemctl status bluetooth-a2dp-autopair"
log ""
log "📚 参考文档："
log "- 使用指南: README.md"
log "- 故障排查: documents/TROUBLESHOOTING.md"
log "- 硬件接线: documents/HW_*.md"
log ""
log "📊 查看实时服务状态："
log "  ./check_status.sh  (在本地电脑运行)"
log ""
log "安装日志已保存: $INSTALL_LOG"
log ""

# 如果有失败的服务，以警告退出码退出（但不中断部署流程）
if [[ $total_failed -gt 0 ]]; then
    log "⚠️  部分服务未启动，但安装流程已完成"
    log "   系统将继续执行重启，服务将在重启后自动修复"
fi

exit 0
