#!/bin/bash
# SD 卡诊断工具 - 检查配置和日志

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || { echo "错误: 无法加载 common.sh"; exit 1; }

require_root

echo_highlight "=== RPI SD 卡诊断工具 ==="
echo ""

# 检测 SD 卡
echo_info "检测 SD 卡..."
DEVICES=()
ROOT_DISK=$(lsblk -no PKNAME $(findmnt -n -o SOURCE /) 2>/dev/null || echo "")

while IFS= read -r line; do
    DEV=$(echo "$line" | awk '{print $1}')
    SIZE=$(echo "$line" | awk '{print $2}')
    MODEL=$(echo "$line" | awk '{$1=$2=""; print $0}' | xargs)
    [ -z "$MODEL" ] && MODEL="Unknown"
    FULL_DEV="/dev/$DEV"
    
    # 跳过系统盘
    [ "$DEV" = "$ROOT_DISK" ] && continue
    
    # 只显示小于 128GB 的设备
    SIZE_GB=$(lsblk -bdno SIZE "$FULL_DEV" 2>/dev/null | awk '{print int($1/1024/1024/1024)}')
    [ "$SIZE_GB" -gt 128 ] && continue
    
    DEVICES+=("$FULL_DEV")
    echo "  [${#DEVICES[@]}] $FULL_DEV ($SIZE) - $MODEL"
done < <(lsblk -dno NAME,SIZE,MODEL 2>/dev/null | grep -v "^loop")

if [ ${#DEVICES[@]} -eq 0 ]; then
    echo_error "未检测到 SD 卡"
    echo_info "请插入 SD 卡后重试"
    exit 1
fi

read -p "选择 SD 卡 [1-${#DEVICES[@]}]: " CHOICE
TARGET_DEVICE="${DEVICES[$((CHOICE-1))]}"

echo ""
echo_success "目标设备: $TARGET_DEVICE"
echo ""

# 显示分区信息
echo_highlight "=== 分区信息 ==="
lsblk "$TARGET_DEVICE" -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
echo ""

# 查找 boot 分区（第一个 FAT 分区）
BOOT_PART=$(lsblk -lnpo NAME,FSTYPE "$TARGET_DEVICE" 2>/dev/null | grep -E "vfat|fat" | head -n1 | awk '{print $1}')
if [ -z "$BOOT_PART" ]; then
    BOOT_PART=$(lsblk -lnpo NAME "$TARGET_DEVICE" 2>/dev/null | grep -E "${TARGET_DEVICE}(p)?1$" | head -n1)
fi

# 查找 root 分区（第二个 ext4 分区）
ROOT_PART=$(lsblk -lnpo NAME,FSTYPE "$TARGET_DEVICE" 2>/dev/null | grep "ext4" | head -n1 | awk '{print $1}')

if [ -z "$BOOT_PART" ]; then
    echo_error "未找到 boot 分区"
    exit 1
fi

echo_success "Boot 分区: $BOOT_PART"
[ -n "$ROOT_PART" ] && echo_success "Root 分区: $ROOT_PART"
echo ""

# 挂载 boot 分区
BOOT_MNT="/tmp/rpi_boot_diag_$$"
mkdir -p "$BOOT_MNT"

umount "$BOOT_PART" 2>/dev/null || true

if ! mount "$BOOT_PART" "$BOOT_MNT" 2>/dev/null; then
    echo_error "挂载 boot 分区失败: $BOOT_PART"
    rmdir "$BOOT_MNT"
    exit 1
fi

echo_success "Boot 分区已挂载到: $BOOT_MNT"
echo ""

# ============================================
# 1. 检查 boot 分区配置文件
# ============================================
echo_highlight "=== [1] Boot 分区配置文件 ==="
echo ""

# userconf.txt
if [ -f "$BOOT_MNT/userconf.txt" ]; then
    echo_info "✓ userconf.txt 存在"
    echo "  大小: $(stat -c%s "$BOOT_MNT/userconf.txt") 字节"
    echo "  内容: $(cat "$BOOT_MNT/userconf.txt")"
    echo ""
    echo "  十六进制视图 (前64字节):"
    xxd "$BOOT_MNT/userconf.txt" | head -n4
    echo ""
    
    # 检查格式
    CONTENT=$(cat "$BOOT_MNT/userconf.txt")
    if [[ "$CONTENT" =~ ^[a-z_][a-z0-9_-]*:\$[0-9]\$ ]]; then
        echo_success "  格式: 正确 (username:hash)"
    else
        echo_error "  格式: 可能有误"
    fi
    
    # 检查换行符
    if [[ "$CONTENT" == *$'\n'* ]]; then
        echo_warning "  警告: 包含换行符（可能导致问题）"
    else
        echo_success "  换行符: 无（正确）"
    fi
else
    echo_warning "✗ userconf.txt 不存在"
fi

echo ""

# user-data (cloud-init)
if [ -f "$BOOT_MNT/user-data" ]; then
    echo_info "✓ user-data 存在"
    echo "  前 20 行:"
    head -n 20 "$BOOT_MNT/user-data" | sed 's/^/    /'
    echo ""
else
    echo_warning "✗ user-data 不存在"
fi

echo ""

# firstrun.sh
if [ -f "$BOOT_MNT/firstrun.sh" ]; then
    echo_info "✓ firstrun.sh 存在"
    echo "  前 15 行:"
    head -n 15 "$BOOT_MNT/firstrun.sh" | sed 's/^/    /'
else
    echo_info "✗ firstrun.sh 不存在（正常）"
fi

echo ""

# SSH
if [ -f "$BOOT_MNT/ssh" ] || [ -f "$BOOT_MNT/ssh.txt" ]; then
    echo_success "✓ SSH 已启用"
else
    echo_warning "✗ SSH 未启用"
fi

echo ""

# WiFi 配置
if [ -f "$BOOT_MNT/wpa_supplicant.conf" ]; then
    echo_info "✓ wpa_supplicant.conf 存在"
    cat "$BOOT_MNT/wpa_supplicant.conf" | sed 's/^/    /'
    echo ""
else
    echo_warning "✗ wpa_supplicant.conf 不存在"
fi

if [ -f "$BOOT_MNT/network-config" ]; then
    echo_info "✓ network-config 存在"
    cat "$BOOT_MNT/network-config" | sed 's/^/    /'
    echo ""
else
    echo_warning "✗ network-config 不存在"
fi

# cmdline.txt
if [ -f "$BOOT_MNT/cmdline.txt" ]; then
    echo_info "✓ cmdline.txt:"
    cat "$BOOT_MNT/cmdline.txt" | sed 's/^/    /'
    echo ""
fi

# config.txt
if [ -f "$BOOT_MNT/config.txt" ]; then
    echo_info "✓ config.txt (相关配置):"
    grep -E "^(enable_uart|dtparam|dtoverlay)" "$BOOT_MNT/config.txt" | sed 's/^/    /' || echo "    (无特殊配置)"
    echo ""
fi

# ============================================
# 2. 挂载并检查 root 分区日志
# ============================================
if [ -n "$ROOT_PART" ]; then
    echo_highlight "=== [2] Root 分区日志分析 ==="
    echo ""
    
    ROOT_MNT="/tmp/rpi_root_diag_$$"
    mkdir -p "$ROOT_MNT"
    
    umount "$ROOT_PART" 2>/dev/null || true
    
    if mount "$ROOT_PART" "$ROOT_MNT" 2>/dev/null; then
        echo_success "Root 分区已挂载到: $ROOT_MNT"
        echo ""
        
        # 检查系统日志
        if [ -d "$ROOT_MNT/var/log" ]; then
            echo_info "检查系统日志..."
            echo ""
            
            # userconfig.service 日志
            echo_info "--- userconfig.service 相关 ---"
            if [ -d "$ROOT_MNT/var/log/journal" ]; then
                echo_warning "日志在 systemd journal 中，需要在树莓派上查看"
                echo_info "命令: journalctl -u userconfig.service"
            fi
            echo ""
            
            # 查找最近的启动日志
            if [ -f "$ROOT_MNT/var/log/syslog" ]; then
                echo_info "--- 最近的 syslog (最后 50 行) ---"
                tail -n 50 "$ROOT_MNT/var/log/syslog" | sed 's/^/  /'
                echo ""
            fi
            
            if [ -f "$ROOT_MNT/var/log/messages" ]; then
                echo_info "--- 最近的 messages (最后 50 行) ---"
                tail -n 50 "$ROOT_MNT/var/log/messages" | sed 's/^/  /'
                echo ""
            fi
            
            # cloud-init 日志
            if [ -f "$ROOT_MNT/var/log/cloud-init.log" ]; then
                echo_info "--- cloud-init.log (最后 30 行) ---"
                tail -n 30 "$ROOT_MNT/var/log/cloud-init.log" | sed 's/^/  /'
                echo ""
            fi
            
            if [ -f "$ROOT_MNT/var/log/cloud-init-output.log" ]; then
                echo_info "--- cloud-init-output.log (最后 30 行) ---"
                tail -n 30 "$ROOT_MNT/var/log/cloud-init-output.log" | sed 's/^/  /'
                echo ""
            fi
            
            # 检查是否有 panic 或 error
            echo_info "--- 搜索关键错误 ---"
            for log in "$ROOT_MNT/var/log/syslog" "$ROOT_MNT/var/log/messages"; do
                if [ -f "$log" ]; then
                    echo_info "在 $(basename $log) 中搜索:"
                    grep -i "userconf\|failed\|error\|panic" "$log" 2>/dev/null | tail -n 20 | sed 's/^/  /' || echo "  (无相关错误)"
                    echo ""
                fi
            done
        else
            echo_warning "未找到 /var/log 目录（可能是首次启动）"
        fi
        
        # 检查用户是否已创建
        echo ""
        echo_info "--- 用户检查 ---"
        if [ -f "$ROOT_MNT/etc/passwd" ]; then
            echo "已存在的用户:"
            grep -v "^#" "$ROOT_MNT/etc/passwd" | grep -v "^root:\|^daemon:\|^sys:" | cut -d: -f1 | sed 's/^/  /'
            echo ""
        fi
        
        # 检查 systemd 服务状态
        if [ -d "$ROOT_MNT/etc/systemd/system" ]; then
            echo_info "--- 相关 systemd 服务 ---"
            ls -la "$ROOT_MNT/etc/systemd/system" | grep -E "userconf|cloud-init|firstboot" | sed 's/^/  /'
            echo ""
        fi
        
        # 卸载 root 分区
        sync
        umount "$ROOT_MNT" 2>/dev/null || umount -l "$ROOT_MNT" 2>/dev/null
        rmdir "$ROOT_MNT" 2>/dev/null || true
    else
        echo_error "无法挂载 root 分区"
    fi
fi

# ============================================
# 3. 诊断总结
# ============================================
echo ""
echo_highlight "=== [3] 诊断总结和建议 ==="
echo ""

# 问题检查清单
ISSUES=0

echo_info "检查项目:"
echo ""

# 1. userconf.txt
if [ ! -f "$BOOT_MNT/userconf.txt" ]; then
    echo_error "✗ userconf.txt 缺失"
    ((ISSUES++))
elif [ ! -s "$BOOT_MNT/userconf.txt" ]; then
    echo_error "✗ userconf.txt 为空"
    ((ISSUES++))
else
    CONTENT=$(cat "$BOOT_MNT/userconf.txt")
    if [[ "$CONTENT" == *$'\n'* ]]; then
        echo_error "✗ userconf.txt 包含换行符（常见问题！）"
        ((ISSUES++))
    elif ! [[ "$CONTENT" =~ ^[a-z_][a-z0-9_-]*:\$[0-9]\$ ]]; then
        echo_warning "⚠ userconf.txt 格式可能有误"
        ((ISSUES++))
    else
        echo_success "✓ userconf.txt 格式正确"
    fi
fi

# 2. user-data 冲突检查
if [ -f "$BOOT_MNT/user-data" ] && [ -f "$BOOT_MNT/userconf.txt" ]; then
    if grep -q "passwd:" "$BOOT_MNT/user-data" 2>/dev/null; then
        echo_warning "⚠ user-data 和 userconf.txt 可能冲突"
        ((ISSUES++))
    else
        echo_success "✓ user-data 和 userconf.txt 不冲突"
    fi
fi

# 3. SSH
if [ ! -f "$BOOT_MNT/ssh" ] && [ ! -f "$BOOT_MNT/ssh.txt" ]; then
    echo_warning "⚠ SSH 未启用（无法远程登录）"
fi

# 4. WiFi
if [ ! -f "$BOOT_MNT/wpa_supplicant.conf" ] && [ ! -f "$BOOT_MNT/network-config" ]; then
    echo_warning "⚠ WiFi 未配置（需要网线连接）"
fi

echo ""

# 给出建议
if [ $ISSUES -gt 0 ]; then
    echo_highlight "发现 $ISSUES 个问题，建议:"
    echo ""
    echo "1. 使用 fix-userconf.sh 修复配置"
    echo "2. 或手动修复后重新写入 SD 卡"
    echo ""
    echo_info "修复命令: sudo ./fix-userconf.sh"
else
    echo_success "配置看起来正常！"
    echo ""
    echo_info "如果仍无法启动，可能是:"
    echo "  1. SD 卡硬件问题"
    echo "  2. 镜像损坏"
    echo "  3. 树莓派硬件问题"
    echo ""
    echo_info "建议通过 HDMI + 键盘查看启动日志"
fi

# 清理
sync
umount "$BOOT_MNT" 2>/dev/null || umount -l "$BOOT_MNT" 2>/dev/null
rmdir "$BOOT_MNT" 2>/dev/null || true

echo ""
echo_success "诊断完成！"
