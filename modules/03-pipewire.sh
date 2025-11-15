################################################################################
# modules/03-pipewire.sh - PipeWire 音频服务
################################################################################
#!/usr/bin/env bash
# 注意：此模块由 stage_2.sh 通过 source 调用，环境已初始化
set -euo pipefail

log "安装 PipeWire 音频服务..."

# ============================================
# 1. 安装软件包
# ============================================
log "1/4. 安装 PipeWire..."
install_pkg pipewire pipewire-pulse wireplumber pipewire-audio-client-libraries

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

sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    systemctl --user daemon-reload

sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    systemctl --user enable pipewire pipewire-pulse wireplumber

# ============================================
# 4. 启动服务并验证
# ============================================
log "4/4. 启动 PipeWire 服务..."

sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    systemctl --user restart pipewire pipewire-pulse wireplumber

# 等待服务就绪
log "等待 PipeWire 就绪..."
wait_for_pipewire


log "✓ PipeWire 安装完成"
log "  服务状态:"
sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    systemctl --user is-active pipewire pipewire-pulse wireplumber | sed 's/^/    /'


