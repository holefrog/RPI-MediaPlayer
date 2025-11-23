#!/usr/bin/env bash
# lib/env.sh

# [关键] 防止重复加载机制
if [[ -n "${__ENV_SH_LOADED:-}" ]]; then
    return 0
fi
declare -g __ENV_SH_LOADED=true


# ============================================
# 全局常量定义（系统路径）
# ============================================
# 1. 根目录（动态获取，无论脚本在哪里被调用，都能定位到项目根目录）
readonly INSTALLER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 2. 项目目录结构定义
readonly RESOURCES_DIR="${INSTALLER_ROOT}/resources"
readonly TEMPLATES_DIR="${INSTALLER_ROOT}/templates"
readonly TEMPLATES_SCRIPTS_DIR="${TEMPLATES_DIR}/scripts"
readonly TEMPLATES_SERVICES_DIR="${TEMPLATES_DIR}/services"
readonly TEMPLATES_CONFIGS_DIR="${TEMPLATES_DIR}/configs"

# 3. 系统标准路径
readonly SYSTEM_BIN_DIR="/usr/local/bin"
readonly SYSTEM_SERVICE_DIR="/etc/systemd/system"

# ============================================
# 环境变量（安装时初始化）
# ============================================
declare -g USER_NAME=""
declare -g USER_HOME=""
declare -g USER_ID=""
declare -g USER_RUNTIME_DIR=""
declare -g INSTALL_LOG=""
declare -g CONFIG_INI=""

# 可配置路径变量（从 config.ini 读取）
declare -g APP_BASE_DIR=""
declare -g OLED_VENV_DIR=""
declare -g OLED_APP_SUBDIR="oled_app"
declare -g BT_CONFIG_SUBDIR="bluetooth" # [保留] 虽然 utils.sh 没用，但 config 里可能用到，建议保留或像上一个回答那样清理
declare -g METADATA_PIPE=""

# 超时配置
declare -g APT_LOCK_TIMEOUT=60
declare -g PIPEWIRE_READY_TIMEOUT=30
declare -g SSH_TIMEOUT=10
declare -g REBOOT_WAIT_TIMEOUT=180
declare -g REBOOT_POLL_INTERVAL=5

# Boot Config 路径
declare -g BOOT_CONFIG=""
declare -g _ENV_READY=false

# ============================================
# 辅助函数：检测 Boot Config
# ============================================
detect_boot_config() {
    for path in "/boot/firmware/config.txt" "/boot/config.txt"; do
        if [[ -f "$path" ]] && [[ -r "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

# ============================================
# 辅助函数：读取配置
# ============================================
_read_config() {
    local section="$1"
    local key="$2"
    local default="${3:-}"
    
    awk -F= -v s="$section" -v k="$key" '
        /^\[.*\]$/ { in_section=0 }
        $0 == "["s"]" { in_section=1; next }
        in_section && $1 == k { 
            gsub(/^[ \t]+|[ \t]+$/, "", $2)
            print $2
            exit 
        }
    ' "$CONFIG_INI" || echo "$default"
}

# ============================================
# 核心函数：初始化安装环境（单一入口）
# ============================================
init_install_env() {
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
    
    # 3. 设置配置路径 (直接使用 INSTALLER_ROOT)
    INSTALL_LOG="${INSTALLER_ROOT}/install.log"
    CONFIG_INI="${INSTALLER_ROOT}/config.ini"

    # [验证] 确保 config.ini 存在
    if [[ ! -f "$CONFIG_INI" ]]; then
        echo "错误: 配置文件不存在: $CONFIG_INI" >&2
        exit 1
    fi
    
    # 4. 从配置文件读取其他应用路径
    # [修改]: 移除了 REMOTE_INSTALL_DIR 的读取，因为它与运行时无关
    APP_BASE_DIR=$(_read_config "paths" "app_base_dir" "rpi-mediaplayer")
    OLED_VENV_DIR=$(_read_config "paths" "oled_venv_dir" ".venv/oled")
    METADATA_PIPE=$(_read_config "paths" "metadata_pipe" "/tmp/shairport-sync-metadata")
    
    # 5. 读取超时配置
    APT_LOCK_TIMEOUT=$(_read_config "timeouts" "apt_lock" "60")
    PIPEWIRE_READY_TIMEOUT=$(_read_config "timeouts" "pipewire_ready" "30")
    SSH_TIMEOUT=$(_read_config "timeouts" "ssh_connect" "10")
    REBOOT_WAIT_TIMEOUT=$(_read_config "timeouts" "reboot_wait" "180")
    REBOOT_POLL_INTERVAL=$(_read_config "timeouts" "reboot_poll_interval" "5")
    
    # [删除]: 原有的 Step 6 (更新 CONFIG_INI 到实际路径) 已删除
    # 这种硬编码拼接路径的方式是不必要的，因为我们在 Step 3 已经定位到了文件
    
    # 6. 创建日志文件
    touch "$INSTALL_LOG" || {
        echo "错误: 无法创建日志文件: $INSTALL_LOG" >&2
        exit 1
    }
    chown "$USER_NAME:$USER_NAME" "$INSTALL_LOG"
    
    # 7. 检测 Boot Config 路径
    BOOT_CONFIG=$(detect_boot_config) || {
        echo "错误: 无法找到 boot config 文件" >&2
        echo "尝试的路径: /boot/firmware/config.txt, /boot/config.txt" >&2
        exit 1
    }
    
    _ENV_READY=true
    
    return 0
}

# ... (保留 require_env 等其他辅助函数) ...
require_env() {
    if [[ "$_ENV_READY" != "true" ]]; then
        echo "错误: 环境未初始化（需先调用 init_install_env）" >&2
        exit 1
    fi
}

get_user_service_dir() {
    require_env
    echo "$USER_HOME/.config/systemd/user"
}

get_app_base_dir() {
    require_env
    echo "$USER_HOME/$APP_BASE_DIR"
}

get_oled_venv_dir() {
    require_env
    echo "$USER_HOME/$OLED_VENV_DIR"
}

get_oled_app_dir() {
    require_env
    echo "$(get_app_base_dir)/$OLED_APP_SUBDIR"
}

# [新增] 配合 07-bluetooth.sh 优化的函数
get_bt_config_dir() {
    require_env
    echo "$USER_HOME/$BT_CONFIG_SUBDIR"
}

get_metadata_pipe() {
    require_env
    echo "$METADATA_PIPE"
}
