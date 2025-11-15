#!/usr/bin/env bash
# lib/utils.sh - 工具函数库（完整优化版）

# 加载环境管理
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# ============================================
# 日志函数
# ============================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() {
    require_env
    local msg="[$(date '+%H:%M:%S')] $*"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$INSTALL_LOG"
}

error() {
    local msg="[$(date '+%H:%M:%S')] ERROR: $*"
    echo -e "${RED}${msg}${NC}" >&2
    [[ -n "${INSTALL_LOG:-}" ]] && echo "$msg" >> "$INSTALL_LOG"
    exit 1
}

warn() {
    local msg="[$(date '+%H:%M:%S')] WARN: $*"
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

install_user_service() {
    require_env
    local service_file="$1"
    local service_name=$(basename "$service_file")
    local service_dir=$(get_user_service_dir)
    
    sudo -u "$USER_NAME" mkdir -p "$service_dir"
    sudo cp "$service_file" "$service_dir/"
    sudo chown "$USER_NAME:$USER_NAME" "$service_dir/$service_name"
    
    log "✓ 用户服务已安装: $service_name"
}

enable_user_service() {
    require_env
    local service_name="$1"
    
    sudo -u "$USER_NAME" \
        XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        systemctl --user daemon-reload
    
    sudo -u "$USER_NAME" \
        XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        systemctl --user enable "$service_name"
    
    log "✓ 用户服务已启用: $service_name"
}

start_user_service() {
    require_env
    local service_name="$1"
    
    sudo -u "$USER_NAME" \
        XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        systemctl --user restart "$service_name"
    
    log "✓ 用户服务已启动: $service_name"
}

stop_user_service() {
    require_env
    local service_name="$1"
    
    sudo -u "$USER_NAME" \
        XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        systemctl --user stop "$service_name" 2>/dev/null || true
    
    log "✓ 用户服务已停止: $service_name"
}

user_service_status() {
    require_env
    local service_name="$1"
    
    sudo -u "$USER_NAME" \
        XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        systemctl --user is-active "$service_name" 2>/dev/null
}

# ============================================
# 模板处理（修复版 - 使用 sed）
# ============================================
install_template_script() {
    require_env
    local template_name="$1"
    local output_name="$2"
    shift 2
    
    local template_file="templates/scripts/${template_name}.template"
    local output_file="${SYSTEM_BIN_DIR}/${output_name}"
    
    [[ -f "$template_file" ]] || error "模板不存在: $template_file"
    
    # 使用临时文件
    local temp_file=$(mktemp)
    cp "$template_file" "$temp_file"
    
    # 使用 sed 进行替换
    for replace in "$@"; do
        local key="${replace%%=*}"
        local value="${replace#*=}"
        
        # 转义 sed 特殊字符（/ \ & 等）
        local escaped_value=$(printf '%s\n' "$value" | sed 's/[\/&]/\\&/g')
        
        # 执行替换（使用 | 作为分隔符避免路径中的 /）
        sed -i "s|{{${key}}}|${escaped_value}|g" "$temp_file"
    done
    
    # 验证替换完成
    if grep -q '{{.*}}' "$temp_file"; then
        warn "警告: 脚本 $output_name 中仍有未替换的变量:"
        grep -o '{{[^}]*}}' "$temp_file" | sort -u | sed 's/^/  /' >&2
    fi
    
    # 移动到目标位置
    sudo mv "$temp_file" "$output_file"
    sudo chmod 755 "$output_file"
    
    log "✓ 脚本已安装: $output_file"
}

install_template_service() {
    require_env
    local template_name="$1"
    local output_name="$2"
    local is_user_service="$3"
    shift 3
    
    local template_file="templates/services/${template_name}.template"
    [[ -f "$template_file" ]] || error "模板不存在: $template_file"
    
    # 使用临时文件
    local temp_file=$(mktemp)
    cp "$template_file" "$temp_file"
    
    log "  替换模板变量..."
    
    # 使用 sed 进行替换
    for replace in "$@"; do
        local key="${replace%%=*}"
        local value="${replace#*=}"
        
        log "    {{$key}} = $value"
        
        # 转义 sed 特殊字符（/ \ & 等）
        local escaped_value=$(printf '%s\n' "$value" | sed 's/[\/&]/\\&/g')
        
        # 执行替换（使用 | 作为分隔符避免路径中的 /）
        sed -i "s|{{${key}}}|${escaped_value}|g" "$temp_file"
    done
    
    # 验证替换完成
    local remaining_vars=$(grep -o '{{[^}]*}}' "$temp_file" 2>/dev/null || true)
    if [[ -n "$remaining_vars" ]]; then
        error "服务文件 $output_name 中有未替换的变量:
$(echo "$remaining_vars" | sort -u | sed 's/^/  /')

已提供的变量:
$(for r in "$@"; do echo "  ${r%%=*}"; done)

模板文件前 20 行:
$(cat "$temp_file" | head -20 | sed 's/^/  /')
"
    fi
    
    # 根据服务类型安装
    if [[ "$is_user_service" == "true" ]]; then
        local service_dir=$(get_user_service_dir)
        local service_file="$service_dir/$output_name"
        
        # 确保目录存在
        sudo -u "$USER_NAME" mkdir -p "$service_dir"
        
        # 移动文件
        sudo mv "$temp_file" "$service_file"
        sudo chown "$USER_NAME:$USER_NAME" "$service_file"
        
        log "✓ 用户服务已安装: $output_name"
        
        # 显示最终内容（调试用）
        if [[ "${DEBUG:-false}" == "true" ]]; then
            log "  服务文件内容:"
            head -15 "$service_file" | sed 's/^/    /' || true
        fi
    else
        local service_file="${SYSTEM_SERVICE_DIR}/${output_name}"
        
        sudo mv "$temp_file" "$service_file"
        sudo systemctl daemon-reload
        
        log "✓ 系统服务已安装: $output_name"
    fi
}

# ============================================
# 等待服务就绪
# ============================================
wait_for_pipewire() {
    require_env
    local timeout="${PIPEWIRE_READY_TIMEOUT:-30}"
    local waited=0
    
    log "等待 PipeWire 就绪..."
    
    while ! sudo -u "$USER_NAME" \
        XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        pactl info >/dev/null 2>&1; do
        
        if [[ $waited -ge $timeout ]]; then
            error "PipeWire 启动超时（${timeout}秒）"
        fi
        
        sleep 1
        waited=$((waited + 1))
    done
    
    log "✓ PipeWire 已就绪"
}

# ============================================
# 调试函数
# ============================================
debug_template_vars() {
    local template_file="$1"
    shift
    
    log "调试: 模板变量检查"
    log "  模板文件: $template_file"
    log "  提供的变量:"
    
    for replace in "$@"; do
        local key="${replace%%=*}"
        local value="${replace#*=}"
        log "    $key = $value"
    done
    
    log "  模板中的变量:"
    if [[ -f "$template_file" ]]; then
        grep -o '{{[^}]*}}' "$template_file" | sort -u | sed 's/^/    /' || log "    (无变量)"
    else
        log "    (文件不存在)"
    fi
}
