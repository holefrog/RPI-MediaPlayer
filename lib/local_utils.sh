#!/usr/bin/env bash
# lib/local_utils.sh - RPI-MediaPlayer 本地脚本公共库

# ============================================
# 1. 全局定义
# ============================================
# 定义要检查的服务列表

# 系统级服务 (需要 systemctl check)
CORE_SYS_SERVICES="bluetooth bluetooth-a2dp-autopair"

# 用户级服务 (需要 systemctl --user check)
CORE_USER_SERVICES="oled pipewire shairport-sync squeezelite volume wireplumber"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[LOCAL] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }

# ============================================
# 2. 环境检查
# ============================================
check_requirements() {
    local missing=0
    for cmd in ssh scp awk sed; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}[✗] 未找到命令: $cmd${NC}"
            ((missing++))
        fi
    done
    if [ $missing -ne 0 ]; then
        error "本地环境缺少必要工具 (ssh, scp, awk, sed)，请先安装。"
    fi
}

# ============================================
# 3. 配置读取
# ============================================
check_config_file() {
    if [[ ! -f "config.ini" ]]; then
        error "config.ini 不存在！请确保你在项目根目录下运行。"
    fi
}

get_config() {
    local section="$1"
    local key="$2"
    awk -F= -v s="$section" -v k="$key" '
        /^\[.*\]$/ { in_section=0 }
        $0 ~ "^\\[" s "\\]" { in_section=1; next }
        in_section && $1 ~ "^[ \t]*" k "[ \t]*$" { 
            val=$2; gsub(/^[ \t]+|[ \t]+$/, "", val); print val; exit 
        }
    ' "config.ini"
}

validate_config() {
    local section="$1"
    local key="$2"
    local val=$(get_config "$section" "$key")
    
    if [[ -z "$val" ]]; then
        error "配置缺失: [$section] $key"
    fi
    echo "$val"
}

# ============================================
# 4. 连接初始化
# 用法: init_connection [mode]
# mode="login": 用于交互式登录 (使用 -t)
# mode="command": 用于远程执行命令 (使用 -T, 默认)
# ============================================
init_connection() {
    # 默认为 'command' 模式，以避免非交互式脚本中的 TTY 警告
    local mode="${1:-command}"

    check_requirements
    check_config_file

    # 读取 SSH 配置
    HOST=$(validate_config "ssh" "host")
    USER=$(validate_config "ssh" "user")
    PORT=$(get_config "ssh" "port")
    PORT="${PORT:-22}" # 默认 22
    
    KEY=$(get_config "ssh" "key")
    # 如果 key 路径是相对路径，转换为基于当前目录的路径
    if [[ "$KEY" == ./* ]]; then
        KEY="$(pwd)/${KEY#./}"
    fi

    # 认证逻辑
    if [[ ! -f "$KEY" ]]; then
         error "未找到 SSH Key ($KEY)。请检查 config.ini 配置。"
    fi

    # 确保密钥权限正确
    chmod 600 "$KEY"
    SSH_CMD="ssh -i $KEY"
    
    # 设置基础 SSH 选项
    local base_opts="-p $PORT -o StrictHostKeyChecking=no -o ConnectTimeout=10"

    # 根据模式设置 TTY 选项
    if [[ "$mode" == "login" ]]; then
        # -t: 强制分配伪终端，用于交互式登录 (如 local_login.sh)
        SSH_OPTS="$base_opts -t"
    else
        # -T: 禁用伪终端分配，用于远程执行命令 (如 check_status.sh)，消除警告
        SSH_OPTS="$base_opts -T"
    fi

    REMOTE="$USER@$HOST"
}
