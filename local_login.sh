#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# 载入公共函数
source lib/local_utils.sh

# 初始化连接：会自动设置
#   HOST, PORT, USER, REMOTE, SSH_CMD, SSH_OPTS
init_connection login # <--- 关键修改: 传入 'login' 模式，强制分配 TTY

echo -e "${GREEN}>>> 正在连接 $HOST (端口: $PORT)...${NC}"

# 清理 known_hosts
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$HOST" >/dev/null 2>&1

# 正式 SSH 登录
# 注意：不需要你手动写 -i 或 -p，它们已包含在 $SSH_OPTS 里
$SSH_CMD $SSH_OPTS "$REMOTE"
