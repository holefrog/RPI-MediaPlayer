#!/usr/bin/env bash
# modules/02-pipewire.sh - PipeWire 音频服务
# 注意：此模块由 stage_2.sh 通过 source 调用，环境已初始化
set -euo pipefail

# 定义模块名称（日志前缀）
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"


log "安装 PipeWire 音频服务..."

# ============================================
# 1. 安装软件包
# ============================================
log "1/4. 安装 PipeWire ..."
# 1. 确保在安装前更新索引（特别是 Lite 系统）
sudo apt-get update 

# 2. 显式包含 pulseaudio-utils 确保 pactl 可用
install_pkg pipewire pipewire-pulse wireplumber pipewire-audio-client-libraries pulseaudio-utils

log "✓ PipeWire 版本信息:"
pipewire --version 2>&1 | head -1 | sed 's/^/  /'

# ============================================
# 2. 启用用户 Linger
# ============================================
log "2/4. 启用用户 Linger..."
enable_linger

# ============================================
# 3. 启用 PipeWire 用户服务
# ============================================
log "3/4. 启用 PipeWire 用户服务..."

run_as_user systemctl --user daemon-reload
run_as_user systemctl --user enable pipewire pipewire-pulse wireplumber

# ============================================
# 4. 启动服务并验证
# ============================================
log "4/4. 启动 PipeWire 服务..."

run_as_user systemctl --user restart pipewire pipewire-pulse wireplumber

# 等待服务就绪
wait_for_pipewire

log "✓ PipeWire 安装完成"
log " 服务状态:"
run_as_user systemctl --user is-active pipewire pipewire-pulse wireplumber | sed 's/^/    /'
