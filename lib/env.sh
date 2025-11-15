#!/usr/bin/env bash
# lib/env.sh - 统一的环境初始化（优化版）

# ============================================
# 全局常量定义
# ============================================
readonly REMOTE_INSTALL_DIR="installer"
readonly SYSTEM_BIN_DIR="/usr/local/bin"
readonly SYSTEM_SERVICE_DIR="/etc/systemd/system"
readonly BOOT_CONFIG="/boot/firmware/config.txt"

# 超时配置
readonly APT_LOCK_TIMEOUT=60
readonly PIPEWIRE_READY_TIMEOUT=30
readonly SSH_TIMEOUT=10
readonly REBOOT_WAIT_TIMEOUT=180
readonly REBOOT_POLL_INTERVAL=5

# ============================================
# 环境变量（安装时初始化）
# ============================================
declare -g USER_NAME=""
declare -g USER_HOME=""
declare -g USER_ID=""
declare -g USER_RUNTIME_DIR=""
declare -g INSTALL_LOG=""
declare -g CONFIG_INI=""

# 初始化标记
declare -g _ENV_READY=false

# ============================================
# 核心函数：初始化安装环境（单一入口）
# ============================================
init_install_env() {
    # 防止重复初始化
    if [[ "$_ENV_READY" == "true" ]]; then
        return 0
    fi
    
    # 1. 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 此脚本需要 root 权限（使用 sudo）" >&2
        exit 1
    fi
    
    # 2. 获取真实用户信息
    USER_NAME="${SUDO_USER:-$(whoami)}"
    
    if ! id "$USER_NAME" &>/dev/null; then
        echo "错误: 用户不存在: $USER_NAME" >&2
        exit 1
    fi
    
    USER_HOME=$(eval echo ~$USER_NAME)
    USER_ID=$(id -u $USER_NAME)
    USER_RUNTIME_DIR="/run/user/$USER_ID"
    
    # 3. 设置安装路径
    INSTALL_LOG="${USER_HOME}/install.log"
    CONFIG_INI="${USER_HOME}/${REMOTE_INSTALL_DIR}/config.ini"
    
    # 4. 创建日志文件
    touch "$INSTALL_LOG" || {
        echo "错误: 无法创建日志文件: $INSTALL_LOG" >&2
        exit 1
    }
    chown "$USER_NAME:$USER_NAME" "$INSTALL_LOG"
    
    # 5. 验证配置文件
    if [[ ! -f "$CONFIG_INI" ]]; then
        echo "错误: 配置文件不存在: $CONFIG_INI" >&2
        exit 1
    fi
    
    # 6. 标记环境已就绪
    _ENV_READY=true
    
    return 0
}

# ============================================
# 辅助函数：确保环境已初始化
# ============================================
require_env() {
    if [[ "$_ENV_READY" != "true" ]]; then
        echo "错误: 环境未初始化（需先调用 init_install_env）" >&2
        exit 1
    fi
}

# ============================================
# 辅助函数：获取用户服务目录
# ============================================
get_user_service_dir() {
    require_env
    echo "$USER_HOME/.config/systemd/user"
}
