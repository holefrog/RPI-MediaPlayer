#!/usr/bin/env bash
# lib/utils.sh

# [关键] 防止重复加载机制
if [[ -n "${__UTILS_SH_LOADED:-}" ]]; then
    return 0
fi
declare -g __UTILS_SH_LOADED=true

# 加载环境管理（即使 env.sh 也有 Guard，这里安全调用即可）
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"


# 设置默认模块名（如果调用脚本未设置）
SCRIPT_NAME="${SCRIPT_NAME:-System}"

# ============================================
# 日志函数 (统一格式: [Time] [Module] [Level] Message)
# ============================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() {
    require_env
    local timestamp=$(date '+%H:%M:%S')
    local msg="[${timestamp}] [${SCRIPT_NAME}] [INFO] $*"
    echo -e "${GREEN}${msg}${NC}"
    
    # 写入日志文件时移除颜色代码
    if [[ -n "${INSTALL_LOG:-}" ]]; then
        echo "$msg" >> "$INSTALL_LOG"
    fi
}

error() {
    local timestamp=$(date '+%H:%M:%S')
    local msg="[${timestamp}] [${SCRIPT_NAME}] [ERROR] $*"
    echo -e "${RED}${msg}${NC}" >&2
    [[ -n "${INSTALL_LOG:-}" ]] && echo "$msg" >> "$INSTALL_LOG"
    exit 1
}

warn() {
    local timestamp=$(date '+%H:%M:%S')
    local msg="[${timestamp}] [${SCRIPT_NAME}] [WARN] $*"
    echo -e "${YELLOW}${msg}${NC}" >&2
    [[ -n "${INSTALL_LOG:-}" ]] && echo "$msg" >> "$INSTALL_LOG"
}

# ============================================
# 配置文件读取
# ============================================
config_get() {
    require_env
    local section="$1"
    local key="$2"
    awk -F= -v s="$section" -v k="$key" '
        /^\[.*\]$/ { in_section=0 }
        $0 == "["s"]" { in_section=1; next }
        in_section && $1 == k { 
            gsub(/^[ \t]+|[ \t]+$/, "", $2)
            print $2
            exit 
        }
    ' "$CONFIG_INI"
}

config_get_or_default() {
    local val=$(config_get "$1" "$2")
    echo "${val:-$3}"
}

config_require() {
    local val=$(config_get "$1" "$2")
    if [[ -z "$val" ]]; then
        error "配置缺失: [$1] $2"
    fi
    echo "$val"
}

module_enabled() {
    local module="$1"
    local enabled=$(config_get "modules" "$module")
    [[ "$enabled" == "yes" ]]
}

# ============================================
# 权限与执行辅助函数 (新增)
# ============================================

# 以目标用户身份运行命令（自动处理环境变量）
run_as_user() {
    require_env
    sudo -u "$USER_NAME" \
        XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        "$@"
}

# 统一执行 pactl 命令
run_pactl() {
    run_as_user pactl "$@"
}

# ============================================
# 包管理
# ============================================
wait_for_apt_lock() {
    local timeout="${APT_LOCK_TIMEOUT:-60}"
    local waited=0
    
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        if [[ $waited -ge $timeout ]]; then
            error "等待 apt 锁超时（${timeout}秒）"
        fi
        log "等待 apt 锁释放... ($waited/$timeout)"
        sleep 5
        waited=$((waited + 5))
    done
}

install_pkg() {
    wait_for_apt_lock
    
    local to_install=()
    for pkg in "$@"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            to_install+=("$pkg")
        fi
    done
    
    if [[ ${#to_install[@]} -eq 0 ]]; then
        log "软件包已安装: $*"
        return 0
    fi
    
    log "安装软件包: ${to_install[*]}"
    if ! sudo apt-get install -y "${to_install[@]}"; then
        error "软件包安装失败: ${to_install[*]}"
    fi
    log "✓ 软件包安装完成"
}

# ============================================
# Systemd 服务管理
# ============================================
enable_linger() {
    require_env
    if ! loginctl show-user "$USER_NAME" -p Linger --value 2>/dev/null | grep -q "yes"; then
        sudo loginctl enable-linger "$USER_NAME"
        log "✓ 启用用户 Linger: $USER_NAME"
    else
        log "用户 Linger 已启用: $USER_NAME"
    fi
}

# --------------------------------------------
# 用户服务管理 (已更新使用 run_as_user)
# --------------------------------------------
install_user_service() {
    require_env
    local service_file="$1"
    local service_name=$(basename "$service_file")
    local service_dir=$(get_user_service_dir)
    
    # 使用 run_as_user 创建目录，确保权限正确
    run_as_user mkdir -p "$service_dir"
    
    sudo cp "$service_file" "$service_dir/"
    sudo chown "$USER_NAME:$USER_NAME" "$service_dir/$service_name"
    
    log "✓ 用户服务已安装: $service_name"
}

enable_user_service() {
    require_env
    local service_name="$1"
    
    run_as_user systemctl --user daemon-reload
    run_as_user systemctl --user enable "$service_name"
    
    log "✓ 用户服务已启用: $service_name"
}

start_user_service() {
    require_env
    local service_name="$1"
    
    run_as_user systemctl --user restart "$service_name"
    
    log "✓ 用户服务已启动: $service_name"
}

stop_user_service() {
    require_env
    local service_name="$1"
    
    run_as_user systemctl --user stop "$service_name" 2>/dev/null || true
    
    log "✓ 用户服务已停止: $service_name"
}

user_service_status() {
    require_env
    local service_name="$1"
    
    run_as_user systemctl --user is-active "$service_name" 2>/dev/null
}

# --------------------------------------------
# 系统服务管理
# --------------------------------------------
system_service_status() {
    local service_name="$1"
    systemctl is-active "$service_name" 2>/dev/null
}

enable_system_service() {
    local service_name="$1"
    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"
    log "✓ 系统服务已启用: $service_name"
}

start_system_service() {
    local service_name="$1"
    sudo systemctl restart "$service_name"
    log "✓ 系统服务已启动: $service_name"
}

# --------------------------------------------
# 统一服务状态检查
# --------------------------------------------
check_service_status() {
    local service_name="$1"
    local service_type="${2:-user}"
    
    if [[ "$service_type" == "user" ]]; then
        user_service_status "$service_name"
    else
        system_service_status "$service_name"
    fi
}

# --------------------------------------------
# 等待服务就绪
# --------------------------------------------
wait_for_service() {
    local service_name="$1"
    local service_type="${2:-user}"
    local timeout="${3:-30}"
    local waited=0
    
    log "等待 $service_name 服务就绪..."
    
    while [[ "$(check_service_status "$service_name" "$service_type")" != "active" ]]; do
        if [[ $waited -ge $timeout ]]; then
            error "$service_name 服务启动超时（${timeout}秒）"
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    log "✓ $service_name 已就绪"
}

# ============================================
# 模板处理
# ============================================
install_template_script() {
    require_env
    local template_name="$1"
    local output_name="$2"
    shift 2
    
    local template_file="${TEMPLATES_SCRIPTS_DIR}/${template_name}.template"
    local output_file="${SYSTEM_BIN_DIR}/${output_name}"
    
    [[ -f "$template_file" ]] || error "模板不存在: $template_file"
    
    local temp_file=$(mktemp)
    cp "$template_file" "$temp_file"
    
    for replace in "$@"; do
        local key="${replace%%=*}"
        local value="${replace#*=}"
        local escaped_value=$(printf '%s\n' "$value" | sed 's/[\/&]/\\&/g')
        sed -i "s|{{${key}}}|${escaped_value}|g" "$temp_file"
    done
    
    if grep -q '{{.*}}' "$temp_file"; then
        warn "警告: 脚本 $output_name 中仍有未替换的变量:"
        grep -o '{{[^}]*}}' "$temp_file" | sort -u | sed 's/^/  /' >&2
    fi
    
    sudo mv "$temp_file" "$output_file"
    sudo chmod 755 "$output_file"
    
    log "✓ 脚本已安装: $output_file"
}

install_template_file() {
    require_env
    local template_source="$1"
    local output_file="$2"
    shift 2
    
    [[ -f "$template_source" ]] || error "模板不存在: $template_source"
    
    local temp_file=$(mktemp)
    cp "$template_source" "$temp_file"
    
    log "生成配置文件: $output_file"
    
    for replace in "$@"; do
        local key="${replace%%=*}"
        local value="${replace#*=}"
        local escaped_value=$(printf '%s\n' "$value" | sed 's/[\/&]/\\&/g')
        sed -i "s|{{${key}}}|${escaped_value}|g" "$temp_file"
    done
    
    local remaining_vars=$(grep -o '{{[^}]*}}' "$temp_file" 2>/dev/null || true)
    if [[ -n "$remaining_vars" ]]; then
        error "文件 $output_file 中有未替换的变量:
$(echo "$remaining_vars" | sort -u | sed 's/^/  /')
"
    fi
    
    sudo mv "$temp_file" "$output_file"
    
    if [[ "$output_file" == /etc/* ]]; then
        sudo chmod 644 "$output_file"
    elif [[ "$output_file" == "$USER_HOME"/* ]]; then
        sudo chown "$USER_NAME:$USER_NAME" "$output_file"
        sudo chmod 644 "$output_file"
    fi
    
    log "✓ 配置文件已安装: $output_file"
}

install_template_service() {
    require_env
    local template_name="$1"
    local output_name="$2"
    local is_user_service="$3"
    shift 3
    
    local template_file="${TEMPLATES_SERVICES_DIR}/${template_name}.template"
    [[ -f "$template_file" ]] || error "模板不存在: $template_file"
    
    local temp_file=$(mktemp)
    cp "$template_file" "$temp_file"
    
    log "替换模板变量..."
    
    for replace in "$@"; do
        local key="${replace%%=*}"
        local value="${replace#*=}"
        log "{{$key}} = $value"
        local escaped_value=$(printf '%s\n' "$value" | sed 's/[\/&]/\\&/g')
        sed -i "s|{{${key}}}|${escaped_value}|g" "$temp_file"
    done
    
    local remaining_vars=$(grep -o '{{[^}]*}}' "$temp_file" 2>/dev/null || true)
    if [[ -n "$remaining_vars" ]]; then
        error "服务文件 $output_name 中有未替换的变量（请检查日志）。"
    fi
    
    if [[ "$is_user_service" == "true" ]]; then
        local service_dir=$(get_user_service_dir)
        local service_file="$service_dir/$output_name"
        
        # 使用 run_as_user 确保目录权限
        run_as_user mkdir -p "$service_dir"
        
        sudo mv "$temp_file" "$service_file"
        sudo chown "$USER_NAME:$USER_NAME" "$service_file"
        
        log "✓ 用户服务已安装: $output_name"
    else
        local service_file="${SYSTEM_SERVICE_DIR}/${output_name}"
        sudo mv "$temp_file" "$service_file"
        # 【关键修复】添加这行，确保服务文件可读
        sudo chmod 644 "$service_file"
        sudo systemctl daemon-reload
        log "✓ 系统服务已安装: $output_name"
    fi
}

# ============================================
# 等待 PipeWire 就绪 (已更新使用 run_pactl)
# ============================================
wait_for_pipewire() {
    require_env
    local timeout="${PIPEWIRE_READY_TIMEOUT:-30}"
    local waited=0
    
    log "等待 PipeWire 就绪..."
    
    # 使用 run_pactl 替代原有的 sudo 调用
    while ! run_pactl info >/dev/null 2>&1; do
        if [[ $waited -ge $timeout ]]; then
            error "PipeWire 启动超时（${timeout}秒）"
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    log "✓ PipeWire 已就绪"
}
