#!/usr/bin/env bash
# stage_2.sh - RPI MediaPlayer 安装 - 第 2 阶段（优化版）
set -euo pipefail

cd "$(dirname "$0")"

# ============================================
# 硬件验证函数
# ============================================
verify_i2c_device() {
    local bus="${1:-1}"
    local addr="${2:-}"
    local dev="/dev/i2c-${bus}"

    if [[ ! -e "$dev" ]]; then
        warn "I2C 设备不存在: $dev"
        return 1
    fi

    if ! command -v i2cdetect &>/dev/null; then
        warn "i2cdetect 命令不存在，请安装 i2c-tools"
        return 1
    fi

    local i2c_result
    i2c_result=$(i2cdetect -y "$bus" 2>/dev/null)

    if [[ -n "$addr" ]]; then
        local addr_hex="${addr#0x}"
        
        if ! echo "$i2c_result" | grep -iq "$addr_hex"; then
            warn "I2C 设备 $dev 上未找到地址 $addr"
            printf "i2cdetect -y %s 结果:\n%s\n" "$bus" "$i2c_result"
            return 2
        fi
        log "✓ I2C 设备验证成功: $dev @ $addr"
    else
        log "✓ I2C 设备存在: $dev"
    fi

    printf "i2cdetect -y %s 结果:\n%s\n" "$bus" "$i2c_result"
    return 0
}

# ============================================
# 1. 加载环境并初始化
# ============================================
[[ -f "lib/utils.sh" ]] || { echo "错误: 找不到 lib/utils.sh" >&2; exit 1; }

source lib/utils.sh

# 初始化环境（单一入口）
init_install_env

# 重定向输出到日志
exec > >(tee -a "$INSTALL_LOG")
exec 2>&1

log "=========================================="
log ">>> 第 2 阶段：服务安装 (重启后)"
log "=========================================="
log "日志文件: $INSTALL_LOG"
log "运行用户: $USER_NAME (UID: $USER_ID)"
log ""

# ============================================
# 2. 硬件验证
# ============================================
log "=========================================="
log ">>> 硬件验证检查"
log "=========================================="

hardware_check_failed=false

# 2.1 检查 WM8960 音频驱动
if module_enabled "audio"; then
    log "验证 WM8960 音频驱动..."
    
    if ! verify_i2c_device "1"; then
        error "I2C-1 总线验证失败！
可能原因:
  1. 未正确配置 /boot/firmware/config.txt
  2. 第 1 阶段后未重启
  3. 硬件连接问题
  
请检查并重新运行部署脚本。"
    fi
    
    if ! aplay -l 2>/dev/null | grep -q "wm8960"; then
        error "WM8960 声卡未检测到！
请检查:
  1. /boot/firmware/config.txt 中的 dtoverlay=wm8960-soundcard
  2. 硬件连接是否正确
  3. 是否已重启系统
  
运行 'aplay -l' 查看详细信息。"
    fi
    
    log "✓ WM8960 音频驱动验证通过"
    aplay -l 2>/dev/null | grep "wm8960" | sed 's/^/  /'
else
    log "跳过 WM8960 验证（audio 模块未启用）"
fi

# 2.2 检查 OLED I2C 设备
if module_enabled "oled"; then
    log "验证 OLED I2C 设备..."
    
    OLED_BUS=$(config_get_or_default "oled" "bus" "1")
    OLED_ADDR=$(config_require "oled" "address")
    
    if ! verify_i2c_device "$OLED_BUS"; then
        warn "I2C-$OLED_BUS 总线未找到"
        warn "OLED 模块将被跳过安装"
        hardware_check_failed=true
    else
        if ! verify_i2c_device "$OLED_BUS" "$OLED_ADDR"; then
            warn "OLED 设备在 I2C-$OLED_BUS @ $OLED_ADDR 未检测到"
            warn "OLED 功能可能无法正常工作"
        else
            log "✓ OLED I2C 设备验证通过 (I2C-$OLED_BUS @ $OLED_ADDR)"
        fi
    fi
else
    log "跳过 OLED 验证（oled 模块未启用）"
fi

log ""

if [ "$hardware_check_failed" = true ]; then
    error "硬件验证失败，无法继续安装。
请检查:
  1. 第 1 阶段是否成功执行
  2. 系统是否已重启
  3. 硬件连接是否正确
  4. /boot/firmware/config.txt 配置是否正确"
fi

log "✓ 所有必需硬件验证通过"
log ""

# ============================================
# 3. 执行第 2 阶段模块
# ============================================
installed_count=0

for module_file in modules/*.sh; do
    module_name=$(basename "$module_file" .sh | cut -d'-' -f2)
    
    # 跳过 system 和 audio 模块
    if [[ "$module_name" == "system" || "$module_name" == "audio" ]]; then
        continue
    fi
    
    # 检查模块是否启用
    if ! module_enabled "$module_name" 2>/dev/null; then
        log "--- 跳过模块: $module_name (未启用) ---"
        continue
    fi
    
    log "=========================================="
    log ">>> 正在安装: $module_name"
    log "=========================================="
    
    # 执行模块安装
    if ! source modules/0*-"${module_name}.sh" 2>&1; then
        error "模块安装失败: $module_name"
    fi
    
    installed_count=$(( installed_count + 1 ))
    log "✓ 模块 $module_name 安装完成"
    log ""
done

# ============================================
# 4. 清理和总结
# ============================================
log "清理孤立依赖包..."
sudo apt-get autoremove -y || warn "无法清理远程孤立依赖包"

log "=========================================="
log "✓ 第 2 阶段完成！成功安装 $installed_count 个服务模块"
log "=========================================="
log "✓ RPI MediaPlayer 全部安装完成！"
log "=========================================="
log ""
log "服务管理命令:"
log "  查看状态: systemctl --user status <service>"
log "  查看日志: journalctl --user -u <service> -f"
log "  重启服务: systemctl --user restart <service>"
log ""
log "已安装的服务:"
if module_enabled "pipewire"; then
    log "  - pipewire.service (音频服务)"
    log "  - pipewire-pulse.service (PulseAudio 兼容)"
fi
if module_enabled "squeezelite"; then
    log "  - squeezelite.service (LMS 播放器)"
fi
if module_enabled "oled"; then
    log "  - oled.service (OLED 显示)"
fi
if module_enabled "airplay"; then
    log "  - shairport-sync.service (AirPlay)"
fi
if module_enabled "bluetooth"; then
    log "  - bluetooth 相关服务"
fi
log ""
log "系统已就绪，所有服务已启动！"



log "=========================================="
