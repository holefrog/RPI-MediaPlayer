#!/usr/bin/env bash
# setup.sh - 本地部署脚本（支持两阶段重启）
set -euo pipefail

cd "$(dirname "$0")"

# ============================================
# 颜色和日志
# ============================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*" >&2; exit 1; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $*" >&2; }

# ============================================
# 1. 加载本地常量和验证
# ============================================
source "lib/env.sh"
readonly CONFIG_FILE="config.ini"

for f in "$CONFIG_FILE" stage_1.sh stage_2.sh; do
    [[ -f "$f" ]] || error "本地文件 $f 不存在"
done
for d in lib modules templates resources; do
    [[ -d "$d" ]] || error "本地目录 $d 不存在"
done

log "✓ 本地文件检查通过"

# ============================================
# 2. 读取 SSH 配置
# ============================================
get_config() {
    awk -F= -v s="$1" -v k="$2" '
        /^\[.*\]$/ { in_section=0 }
        $0 == "["s"]" { in_section=1; next }
        in_section && $1 == k { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }
    ' "$CONFIG_FILE"
}

SSH_HOST=$(get_config "ssh" "host")
SSH_USER=$(get_config "ssh" "user")
SSH_PORT=$(get_config "ssh" "port")
SSH_KEY=$(get_config "ssh" "key")

[[ -z "$SSH_HOST" ]] && error "SSH 配置缺失: [ssh] host"
[[ -z "$SSH_USER" ]] && error "SSH 配置缺失: [ssh] user"
[[ -z "$SSH_KEY" ]] && error "SSH 配置缺失: [ssh] key"
[[ -z "$SSH_PORT" ]] && SSH_PORT=22

[[ -f "$SSH_KEY" ]] || error "SSH 密钥不存在: $SSH_KEY"
chmod 600 "$SSH_KEY" 2>/dev/null || true

readonly REMOTE="$SSH_USER@$SSH_HOST"

# SSH 命令优化
readonly SSH_OPTS="-i $SSH_KEY -p $SSH_PORT -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
readonly SSH_CMD="ssh $SSH_OPTS -o ConnectTimeout=$SSH_TIMEOUT"
readonly SCP_CMD="scp -i $SSH_KEY -P $SSH_PORT -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

log "✓ SSH 配置加载: $REMOTE (端口: $SSH_PORT)"

# ============================================
# 3. 测试 SSH 连接
# ============================================
log "测试 SSH 连接..."
if ! $SSH_CMD "$REMOTE" "echo 'SSH 连接成功'" 2>/dev/null; then
    error "SSH 连接失败: $REMOTE"
fi
log "✓ SSH 连接测试成功"

# ============================================
# 4. 重启和等待函数（提取）
# ============================================

# 函数：执行远程重启并等待上线
# 参数：
#   $1 - 重启描述信息（用于日志）
reboot_and_wait() {
    local description="${1:-系统}"
    
    log "=========================================="
    log ">>> [重启] ${description}，正在重启 RPi..."
    log "=========================================="
    
    # 发送重启命令（后台执行，忽略连接断开）
    $SSH_CMD "$REMOTE" "sudo reboot" >/dev/null 2>&1 &
    sleep 2
    
    # 等待 RPi 离线
    log "等待 RPi 离线..."
    sleep 5
    while $SSH_CMD "$REMOTE" "echo" >/dev/null 2>&1; do
        sleep $REBOOT_POLL_INTERVAL
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
        sleep $REBOOT_POLL_INTERVAL
    done
    echo ""
    log "✓ RPi 已重新上线！"
    echo ""
}

# ============================================
# 5. 确认部署
# ============================================
echo ""
log "=========================================="
log "  RPI MediaPlayer 部署工具"
log "=========================================="
log "目标主机: $REMOTE"
echo ""
log "启用的模块:"
awk -F= '/^\[modules\]/{f=1;next} /^\[/{f=0} f && $2=="yes"{printf "  ✓ %s\n", $1}' "$CONFIG_FILE"
echo ""
read -p "确认部署? (yes/no): " confirm
[[ "$confirm" == "yes" ]] || { echo "已取消"; exit 0; }
echo ""

# ============================================
# 6. 上传文件
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
# 7. 执行安装 - 第 1 阶段
# ============================================
log "=========================================="
log ">>> [执行] 第 1 阶段：系统配置"
log "=========================================="
echo ""

$SSH_CMD -t "$REMOTE" "cd $REMOTE_TMP_DIR && sudo ./stage_1.sh" || error "第 1 阶段安装失败"

echo ""
log "✓ 第 1 阶段执行完毕"

# ============================================
# 8. 第一次重启（Stage 1 完成后）
# ============================================
# reboot_and_wait "第 1 阶段完成"

# ============================================
# 9. 执行安装 - 第 2 阶段
# ============================================
log "=========================================="
log ">>> [执行] 第 2 阶段：服务安装"
log "=========================================="
echo ""

$SSH_CMD -t "$REMOTE" "cd $REMOTE_TMP_DIR && sudo ./stage_2.sh" || error "第 2 阶段安装失败"

echo ""
log "✓ 第 2 阶段执行完毕"

# ============================================
# 10. 第二次重启（Stage 2 完成后）
# ============================================
reboot_and_wait "第 2 阶段完成"

# ============================================
# 11. 清理和完成
# ============================================
log "=========================================="
log "✓ 部署完成！"
log "=========================================="
log "清理临时文件..."
$SSH_CMD "$REMOTE" "rm -rf $REMOTE_TMP_DIR" || warn "无法清理远程临时文件夹"

log "=========================================="
log "系统已就绪，所有服务已启动"
log "=========================================="
