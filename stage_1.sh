#!/usr/bin/env bash
# stage_1.sh - RPI MediaPlayer 安装 - 第 1 阶段（优化版）
set -euo pipefail

cd "$(dirname "$0")"

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
log "  RPI MediaPlayer 安装程序"
log ">>> 第 1 阶段：系统配置"
log "=========================================="
log "日志文件: $INSTALL_LOG"
log "运行用户: $USER_NAME (UID: $USER_ID)"
log ""

# ============================================
# 2. 检查模块依赖
# ============================================
log "检查模块依赖..."

if module_enabled "squeezelite" || module_enabled "airplay" || module_enabled "volume"; then
    module_enabled "pipewire" || error "依赖错误: squeezelite/airplay/volume 需要 pipewire 模块"
fi

if module_enabled "pipewire" && ! module_enabled "audio"; then
    warn "建议: pipewire 依赖音频驱动，建议启用 audio 模块"
fi

module_enabled "system" || error "system 模块必须启用"

log "✓ 模块依赖检查通过"
log ""

# ============================================
# 3. 执行第 1 阶段模块
# ============================================
log ">>> 正在执行: 01-system.sh"
log "=========================================="

# 直接 source 模块（继承环境）
source modules/01-system.sh || error "系统配置失败 (modules/01-system.sh)"

log "=========================================="
log "✓ 第 1 阶段完成"
log "安装程序将退出，部署脚本 (setup.sh) 将处理重启"
log "=========================================="
