#!/usr/bin/env bash
# lib/monitor.sh
# 此脚本通过 SSH 在远程执行
# 参数: $1=系统服务列表, $2=用户服务列表

# 1. 接收参数
SYS_SERVICES="${1:-}"
USER_SERVICES="${2:-}"

# 2. 关键修复：设置用户级服务所需的环境变量
# SSH 非交互模式下通常缺少此变量，导致 systemctl --user 失败
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# 定义颜色
Y='\033[1;33m'; G='\033[0;32m'; R='\033[0;31m'; C='\033[0;36m'; NC='\033[0m'

# 辅助函数：获取 CPU 温度
get_rpi_temp() {
    if command -v vcgencmd &> /dev/null; then
        vcgencmd measure_temp | cut -d= -f2
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        awk '{printf "%.1f'\''C\n", $1/1000}' /sys/class/thermal/thermal_zone0/temp
    else
        echo "N/A"
    fi
}

# 获取系统信息
CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -1 | awk -F': ' '{print $2}' | sed 's/^[ \t]*//')
[[ -z "$CPU_MODEL" ]] && CPU_MODEL=$(grep 'Model' /proc/cpuinfo | head -1 | awk -F': ' '{print $2}')

echo -e "\n${Y}=== 🍓 硬件与系统 (Raspberry Pi) ===${NC}"
echo "OS 版本:  $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
echo "内核版本: $(uname -r)"
echo "硬件型号: ${CPU_MODEL:-Unknown}"
echo -e "CPU 温度: ${C}$(get_rpi_temp)${NC}"

# 检查电源降频状态
if command -v vcgencmd &> /dev/null; then
    THROTTLED=$(vcgencmd get_throttled | cut -d= -f2)
    if [[ "$THROTTLED" != "0x0" ]]; then
        echo -e "电源状态: ${R}⚠️ 检测到降频/欠压 (代码: $THROTTLED)${NC}"
    fi
fi

echo -e "\n${Y}=== ⏱️  运行状态 ===${NC}"
uptime -p | sed 's/up /已运行: /'
echo "系统负载: $(uptime | awk -F'load average:' '{ print $2 }')"
echo -e "IP 地址 : ${C}$(hostname -I | awk '{print $1}')${NC}"

echo -e "\n${Y}=== 💾 资源使用 ===${NC}"
free -h | awk '/^Mem:/ {print "物理内存: 总计 " $2 " / 已用 " $3 " (可用 " $7 ")"}'
df -h / | awk 'NR==2 {print "SD卡存储: 总计 " $2 " / 已用 " $3 " (" $5 ")"}'

# 函数：检查服务状态 (增强健壮性)
check_svc() {
    local name="$1"
    local type="$2" # 'system' or 'user'
    local cmd="systemctl"
    
    [[ "$type" == "user" ]] && cmd="systemctl --user"
    
    # 第一步：检查服务单元文件是否存在
    # 使用 cat 而非 status 避免此时就需要 DBus 连接
    if ! $cmd cat "${name}.service" >/dev/null 2>&1; then
        printf " %-22s \t[${type}]\t${Y}未安装${NC}\n" "$name"
        return
    fi

    # 第二步：检查运行状态
    # 如果是用户服务且 XDG_RUNTIME_DIR 仍有问题，这里可能会报错，我们将其捕获为“未知/错误”
    if $cmd is-active --quiet "$name"; then
        printf " %-22s \t[${type}]\t${G}运行中${NC}\n" "$name"
    else
        # 再次检查是否是因为 failed
        if $cmd is-failed --quiet "$name"; then
            printf " %-22s \t[${type}]\t${R}已失败${NC}\n" "$name"
        else
            printf " %-22s \t[${type}]\t${R}已停止${NC}\n" "$name"
        fi
    fi
}

echo -e "\n${Y}=== 🚦 核心服务状态 ===${NC}"

# 检查系统级服务
for svc in $SYS_SERVICES; do
    [[ -n "$svc" ]] && check_svc "$svc" "system"
done

# 检查用户级服务
for svc in $USER_SERVICES; do
    [[ -n "$svc" ]] && check_svc "$svc" "user"
done

echo ""
