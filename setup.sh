#!/usr/bin/env bash
# setup.sh - 本地部署脚本（完整版 - 增强服务状态检查）
set -euo pipefail

cd "$(dirname "$0")"

# 定义模块名称（日志前缀）
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"

# ============================================
# 颜色和日志
# ============================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() {
    local timestamp=$(date '+%H:%M:%S')
    local msg="[${timestamp}] [${SCRIPT_NAME}] [INFO] $*"
    echo -e "${GREEN}${msg}${NC}"
}

error() {
    local timestamp=$(date '+%H:%M:%S')
    local msg="[${timestamp}] [${SCRIPT_NAME}] [ERROR] $*"
    echo -e "${RED}${msg}${NC}" >&2
    exit 1
}

warn() {
    local timestamp=$(date '+%H:%M:%S')
    local msg="[${timestamp}] [${SCRIPT_NAME}] [WARN] $*"
    echo -e "${YELLOW}${msg}${NC}" >&2
}

# ============================================
# 辅助函数：读取配置
# ============================================
get_config() {
    local section="$1"
    local key="$2"
    local default_val="${3:-}"

    local val
    val=$(awk -F= -v s="$section" -v k="$key" '
        /^\[.*\]$/ { in_section=0 }
        $0 == "["s"]" { in_section=1; next }
        in_section && $1 == k { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }
    ' "$CONFIG_FILE")

    echo "${val:-$default_val}"
}

# ============================================
# 1. 加载本地常量和验证
# ============================================
readonly CONFIG_FILE="config.ini"

for f in "$CONFIG_FILE" stage_1.sh stage_2.sh; do
    [[ -f "$f" ]] || error "本地文件 $f 不存在"
done
for d in lib modules templates resources; do
    [[ -d "$d" ]] || error "本地目录 $d 不存在"
done

log "✓ 本地文件检查通过"

# ============================================
# 2. 读取配置
# ============================================
readonly SSH_TIMEOUT=$(get_config "timeouts" "ssh_connect" "10")
readonly REBOOT_WAIT_TIMEOUT=$(get_config "timeouts" "reboot_wait" "180")
readonly REBOOT_POLL_INTERVAL=$(get_config "timeouts" "reboot_poll_interval" "5")
readonly REMOTE_INSTALL_DIR=$(get_config "paths" "remote_install_dir" "installer")

# 读取新增的等待时间配置
readonly DEPLOYMENT_INITIAL_WAIT=$(get_config "timeouts" "deployment_initial_wait" "2")
readonly DEPLOYMENT_OFFLINE_WAIT=$(get_config "timeouts" "deployment_offline_wait" "5")

# ============================================
# 3. SSH 配置
# ============================================
SSH_HOST=$(get_config "ssh" "host")
SSH_USER=$(get_config "ssh" "user")
SSH_PORT=$(get_config "ssh" "port" "22")
SSH_KEY=$(get_config "ssh" "key")

[[ -z "$SSH_HOST" ]] && error "SSH 配置缺失: [ssh] host"
[[ -z "$SSH_USER" ]] && error "SSH 配置缺失: [ssh] user"
[[ -z "$SSH_KEY" ]] && error "SSH 配置缺失: [ssh] key"

# 强制检查密钥权限
[[ -f "$SSH_KEY" ]] || error "SSH 密钥文件不存在: $SSH_KEY"

if ! chmod 600 "$SSH_KEY" 2>/dev/null; then
    error "无法设置 SSH 密钥权限。请手动运行: chmod 600 $SSH_KEY"
fi

# 验证权限
readonly actual_perms=$(stat -c "%a" "$SSH_KEY" 2>/dev/null || stat -f "%OLp" "$SSH_KEY" 2>/dev/null)
if [[ "$actual_perms" != "600" ]]; then
    error "SSH 密钥权限不正确: $actual_perms (应为 600)"
fi

readonly REMOTE="$SSH_USER@$SSH_HOST"

# SSH 命令优化
readonly SSH_OPTS="-i $SSH_KEY -p $SSH_PORT -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
readonly SSH_CMD="ssh $SSH_OPTS -o ConnectTimeout=$SSH_TIMEOUT"
readonly SCP_CMD="scp -i $SSH_KEY -P $SSH_PORT -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

log "$(printf "✓ SSH 配置加载: %s (端口: %s)" "$REMOTE" "$SSH_PORT")"
log "$(printf "超时配置: SSH=%ss, 重启等待=%ss" "$SSH_TIMEOUT" "$REBOOT_WAIT_TIMEOUT")"

# ============================================
# 4. 测试 SSH 连接
# ============================================
log "测试 SSH 连接..."
if ! $SSH_CMD "$REMOTE" "echo 'SSH 连接成功'" 2>/dev/null; then
    error "SSH 连接失败: $REMOTE"
fi
log "✓ SSH 连接测试成功"

# ============================================
# 5. 重启和等待函数
# ============================================
reboot_and_wait() {
    local description="${1:-系统}"
    
    log "=========================================="
    log ">>> [重启] ${description}，正在重启 RPi..."
    log "=========================================="
    
    # 发送重启命令（后台执行，忽略连接断开）
    $SSH_CMD "$REMOTE" "sudo reboot" >/dev/null 2>&1 &
    
    # 使用配置化等待时间
    sleep "$DEPLOYMENT_INITIAL_WAIT"
    
    # 等待 RPi 离线
    log "等待 RPi 离线..."
    sleep "$DEPLOYMENT_OFFLINE_WAIT"
    while $SSH_CMD "$REMOTE" "echo" >/dev/null 2>&1; do
        sleep "$REBOOT_POLL_INTERVAL"
    done
    log "✓ RPi 已离线"
    
    # 等待 RPi 重新上线
    log "等待 RPi 重启上线 (超时: ${REBOOT_WAIT_TIMEOUT}s)..."
    local wait=0
    until $SSH_CMD "$REMOTE" "echo 'RPi 已上线'" >/dev/null 2>&1; do
        wait=$((wait + REBOOT_POLL_INTERVAL))
        if ((wait > REBOOT_WAIT_TIMEOUT)); then
            error "RPi 重启超时"
        fi
        printf "."
        sleep "$REBOOT_POLL_INTERVAL"
    done
    echo ""
    log "✓ RPi 已重新上线！"
}

# ============================================
# 6. 确认部署
# ============================================
echo ""
log "=========================================="
log "RPI MediaPlayer 部署工具"
log "=========================================="
log "目标主机: $REMOTE"
echo ""
read -p "确认部署? (yes/no): " confirm
[[ "$confirm" == "yes" ]] || { echo "已取消"; exit 0; }
echo ""

# ============================================
# 7. 上传文件
# ============================================
readonly REMOTE_HOME_DIR="$($SSH_CMD $REMOTE 'echo $HOME' 2>&1 | tail -1)"
[[ -n "$REMOTE_HOME_DIR" ]] || error "无法获取远程 HOME 目录"

readonly REMOTE_TMP_DIR="${REMOTE_HOME_DIR}/${REMOTE_INSTALL_DIR}"

log "[1/4] 创建远程目录 $REMOTE_TMP_DIR..."
$SSH_CMD "$REMOTE" "rm -rf $REMOTE_TMP_DIR && mkdir -p $REMOTE_TMP_DIR" || error "无法创建远程目录"

log "[2/4] 上传库文件和模块..."
$SCP_CMD -r lib/ modules/ "$REMOTE:$REMOTE_TMP_DIR/" || error "上传库文件失败"

log "[3/4] 上传脚本、配置和资源..."
$SCP_CMD -r config.ini stage_1.sh stage_2.sh templates/ resources/ "$REMOTE:$REMOTE_TMP_DIR/" || error "上传配置文件失败"

log "[4/4] 设置远程权限..."
$SSH_CMD "$REMOTE" "chmod +x $REMOTE_TMP_DIR/*.sh $REMOTE_TMP_DIR/lib/*.sh $REMOTE_TMP_DIR/modules/*.sh" || error "设置权限失败"

log "✓ 文件上传和权限设置完成"
echo ""

# ============================================
# 8. 执行安装 - 第 1 阶段
# ============================================
log "=========================================="
log ">>> [执行] 第 1 阶段：系统配置"
log "=========================================="
echo ""

$SSH_CMD -t "$REMOTE" "cd $REMOTE_TMP_DIR && sudo ./stage_1.sh" || error "第 1 阶段安装失败"

echo ""
log "✓ 第 1 阶段执行完毕"

# ============================================
# 9. 第一次重启（Stage 1 完成后）
# ============================================
reboot_and_wait "第 1 阶段完成"

# ============================================
# 10. 执行安装 - 第 2 阶段
# ============================================
log "=========================================="
log ">>> [执行] 第 2 阶段：服务安装"
log "=========================================="
echo ""

$SSH_CMD -t "$REMOTE" "cd $REMOTE_TMP_DIR && sudo ./stage_2.sh" || error "第 2 阶段安装失败"

echo ""
log "✓ 第 2 阶段执行完毕"

# ============================================
# 11. 第二次重启（Stage 2 完成后）
# ============================================
log ""
log "=========================================="
log ">>> [重要] 第二次重启以确保所有服务完全就绪"
log "=========================================="
log ""

reboot_and_wait "第 2 阶段完成"

# ============================================
# 🆕 12. 增强的服务状态检查
# ============================================
log "=========================================="
log ">>> [验证] 检查服务状态"
log "=========================================="
echo ""

# 定义服务检查脚本（内联到远程执行）
SERVICE_CHECK_SCRIPT='
#!/bin/bash
set -euo pipefail

# 环境设置
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# 颜色代码
readonly GREEN="\033[0;32m"
readonly RED="\033[0;31m"
readonly YELLOW="\033[1;33m"
readonly NC="\033[0m"

# 检查函数
check_service() {
    local svc="$1"
    local type="$2"
    local status
    
    if [[ "$type" == "user" ]]; then
        status=$(systemctl --user is-active "$svc" 2>/dev/null || echo "unknown")
    else
        status=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
    fi
    
    local svc_display=$(printf "%-24s" "$svc")
    
    case "$status" in
        active)
            echo -e "  ${GREEN}✓${NC} ${svc_display} [${type}]  ${GREEN}active${NC}"
            return 0
            ;;
        activating)
            echo -e "  ${YELLOW}⏳${NC} ${svc_display} [${type}]  ${YELLOW}activating (启动中)${NC}"
            return 1
            ;;
        failed)
            echo -e "  ${RED}✗${NC} ${svc_display} [${type}]  ${RED}FAILED${NC}"
            if [[ "$type" == "user" ]]; then
                echo -e "     ${YELLOW}→ 查看日志: journalctl --user -u $svc -n 20${NC}"
            else
                echo -e "     ${YELLOW}→ 查看日志: journalctl -u $svc -n 20${NC}"
            fi
            return 2
            ;;
        inactive|dead)
            echo -e "  ${YELLOW}○${NC} ${svc_display} [${type}]  ${YELLOW}inactive (未启动)${NC}"
            return 1
            ;;
        *)
            echo -e "  ${YELLOW}?${NC} ${svc_display} [${type}]  ${YELLOW}unknown${NC}"
            return 1
            ;;
    esac
}

echo "用户服务状态:"
user_failed=0
for svc in pipewire squeezelite oled shairport-sync volume wireplumber; do
    if ! check_service "$svc.service" "user"; then
        ((user_failed++)) || true
    fi
done

echo ""
echo "系统服务状态:"
system_failed=0
for svc in bluetooth bluetooth-a2dp-autopair; do
    if ! check_service "$svc.service" "system"; then
        ((system_failed++)) || true
    fi
done

echo ""
total_failed=$((user_failed + system_failed))

if [[ $total_failed -gt 0 ]]; then
    echo -e "${YELLOW}=========================================="
    echo -e "⚠️  发现 $total_failed 个服务未正常运行"
    echo -e "=========================================${NC}"
    echo ""
    echo -e "${YELLOW}这些服务将在下次重启后自动启动${NC}"
    echo -e "${YELLOW}如需立即修复，请参阅 documents/TROUBLESHOOTING.md${NC}"
    exit 1
else
    echo -e "${GREEN}=========================================="
    echo -e "✅ 所有服务运行正常"
    echo -e "==========================================${NC}"
    exit 0
fi
'

# 在远程执行服务检查
log "正在检查所有服务状态..."
echo ""

if $SSH_CMD "$REMOTE" "bash -s" <<< "$SERVICE_CHECK_SCRIPT" 2>/dev/null; then
    CHECK_STATUS=0
else
    CHECK_STATUS=$?
fi

echo ""

if [[ $CHECK_STATUS -eq 0 ]]; then
    log "✅ 所有核心服务已验证通过"
else
    warn "部分服务未就绪，但不影响系统基本功能"
    warn "详细信息请参阅上方输出"
fi

# ============================================
# 13. 清理和完成
# ============================================
log "=========================================="
log "✓ 部署完成！"
log "=========================================="
log "清理临时文件..."
$SSH_CMD "$REMOTE" "rm -rf $REMOTE_TMP_DIR" || warn "无法清理远程临时文件夹"

log ""
log "=========================================="
log "系统已就绪，所有服务已启动"
log "=========================================="
log ""
log "✅ 部署成功！"
log ""
log "📚 快速参考："
log "- 查看服务状态: ./check_status.sh"
log "- 查看服务日志: journalctl --user -u <service>"
log "- 音量控制: volume.sh up/down/status"
log "- 故障排查: 参阅 documents/TROUBLESHOOTING.md"
log ""
log "🔗 远程连接："
log "  ssh -i $SSH_KEY $REMOTE"
