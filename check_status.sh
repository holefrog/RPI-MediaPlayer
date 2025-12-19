#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# 引用公共库
source lib/local_utils.sh

# 1. 初始化连接
init_connection

# 2. 准备服务列表
SYS_SVCS="$CORE_SYS_SERVICES"
USER_SVCS="$CORE_USER_SERVICES"

echo -e "${GREEN}>>> 正在连接 $HOST (用户: $USER | 端口: $PORT)...${NC}"

# 3. 远程执行
# 【关键修复】我们需要手动构造远程命令字符串，并对引号进行转义
# 这样 SSH 发送给远程的命令类似于： bash -s -- "svc1 svc2" "svc3 svc4"
# 从而确保 $1 和 $2 能接收到完整的列表字符串
REMOTE_CMD="bash -s -- \"$SYS_SVCS\" \"$USER_SVCS\""

$SSH_CMD $SSH_OPTS "$REMOTE" "$REMOTE_CMD" < lib/monitor.sh
