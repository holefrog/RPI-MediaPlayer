#!/usr/bin/env bash
# 注意：此模块由 stage_2.sh 通过 source 调用，环境已初始化
set -euo pipefail

log "安装 OLED 显示屏..."

# ============================================
# 1. 读取配置
# ============================================
log "1/9. 读取配置..."

OLED_TYPE=$(config_require "oled" "type")
OLED_BUS=$(config_get_or_default "oled" "bus" "1")
OLED_ADDR=$(config_require "oled" "address")
OLED_WIDTH=$(config_require "oled" "width")
OLED_HEIGHT=$(config_require "oled" "height")

log "  OLED 类型: $OLED_TYPE"
log "  I2C 总线: $OLED_BUS"
log "  I2C 地址: $OLED_ADDR"
log "  分辨率: ${OLED_WIDTH}x${OLED_HEIGHT}"

# ============================================
# 2. 验证参数
# ============================================
log "2/9. 验证配置参数..."

if [[ "$OLED_TYPE" != "ssd1306" ]]; then
    error "不支持的 OLED 类型: $OLED_TYPE (仅支持 ssd1306)"
fi

if ! echo "$OLED_ADDR" | grep -Eq '^0x[0-9A-Fa-f]{2}$'; then
    error "I2C 地址格式错误: $OLED_ADDR (应为 0xXX)"
fi

if ! [[ "$OLED_BUS" =~ ^[0-9]+$ ]]; then
    error "I2C 总线编号格式错误: $OLED_BUS (应为数字)"
fi

log "✓ 配置参数验证通过"

# ============================================
# 3. I2C 设备验证（已在 stage_2 检查，这里仅记录）
# ============================================
log "3/9. I2C 设备状态..."
log "  (硬件验证已在 Stage 2 完成)"

I2C_DEV="/dev/i2c-${OLED_BUS}"
if [[ -e "$I2C_DEV" ]]; then
    log "✓ I2C 设备存在: $I2C_DEV"
else
    warn "I2C 设备不存在: $I2C_DEV (将尝试继续安装)"
fi

# ============================================
# 4. 安装系统依赖
# ============================================
log "4/9. 安装系统依赖..."

install_pkg python3 python3-pip python3-venv python3-smbus python3-pillow

# 验证 Python
if ! command -v python3 &>/dev/null; then
    error "Python3 未正确安装"
fi

log "✓ Python 版本: $(python3 --version)"

# ============================================
# 5. 创建 Python 虚拟环境
# ============================================
log "5/9. 创建 Python 虚拟环境..."

VENV_DIR="$USER_HOME/.venv/oled"

if [[ -d "$VENV_DIR" ]]; then
    log "  虚拟环境已存在，删除旧版本..."
    sudo rm -rf "$VENV_DIR"
fi

if ! sudo -u "$USER_NAME" python3 -m venv "$VENV_DIR"; then
    error "虚拟环境创建失败"
fi

# 验证虚拟环境
if [[ ! -f "$VENV_DIR/bin/python" ]]; then
    error "虚拟环境未正确创建"
fi

log "✓ 虚拟环境已创建: $VENV_DIR"

# ============================================
# 6. 安装 Python 库
# ============================================
log "6/9. 安装 Python 库..."

# 升级 pip
if ! sudo -u "$USER_NAME" "$VENV_DIR/bin/pip" install --upgrade pip >/dev/null 2>&1; then
    error "pip 升级失败"
fi

# 安装必需库
if ! sudo -u "$USER_NAME" "$VENV_DIR/bin/pip" install \
        luma.oled \
        requests >/dev/null 2>&1; then
    error "OLED 库安装失败"
fi

log "✓ Python 库安装完成"

# ============================================
# 7. 部署 OLED 测试脚本 (★ 已修改)
# ============================================
log "7/9. 部署 OLED 测试脚本..."

# 定义资源路径
readonly LOCAL_RESOURCE_DIR="$(dirname "${BASH_SOURCE[0]}")/../resources/oled"
readonly TEST_SCRIPT_NAME="oled_test.py"
readonly TEST_SCRIPT_SOURCE="$LOCAL_RESOURCE_DIR/$TEST_SCRIPT_NAME"
# $SYSTEM_BIN_DIR 来自 lib/env.sh
readonly TEST_SCRIPT_DEST="$SYSTEM_BIN_DIR/oled_test.py" 

if [[ ! -f "$TEST_SCRIPT_SOURCE" ]]; then
    error "OLED 测试脚本未找到: $TEST_SCRIPT_SOURCE"
fi

# 复制脚本到 /usr/local/bin (由 $SYSTEM_BIN_DIR 定义)
sudo cp "$TEST_SCRIPT_SOURCE" "$TEST_SCRIPT_DEST"
sudo chmod 755 "$TEST_SCRIPT_DEST"

log "✓ 测试脚本已安装: $TEST_SCRIPT_DEST"

# ============================================
# 8. 测试 OLED（仅在设备存在时）(★ 已修改)
# ============================================
log "8/9. 测试 OLED 显示..."

if [[ -e "$I2C_DEV" ]]; then
    log "  运行测试（将显示 20 秒）..."
    
    # 动态调用参数化的 Python 脚本
    # 使用从 config.ini 读取的变量
    if timeout 25 sudo -u "$USER_NAME" "$VENV_DIR/bin/python" \
        "$TEST_SCRIPT_DEST" \
        --bus "$OLED_BUS" \
        --address "$OLED_ADDR" \
        --width "$OLED_WIDTH" \
        --height "$OLED_HEIGHT"; then
        
        log "✓ OLED 测试成功"
    else
        warn "OLED 测试失败。请仔细检查 config.ini [oled] 设置及硬件连接"
        warn "  - 检查的总线 (Bus): $OLED_BUS (设备: $I2C_DEV)"
        warn "  - 检查的地址 (Address): $OLED_ADDR"
        warn "  - 检查的分辨率: ${OLED_WIDTH}x${OLED_HEIGHT}"
    fi
    
else
    log "  跳过测试（I2C 设备不存在: $I2C_DEV）"

fi

# ============================================
# 9. 部署 OLED 应用和服务
# ============================================
log "9/9. 部署 OLED 应用和服务..."

OLED_APP_DIR="$USER_HOME/rpi-mediaplayer/oled_app"
RESOURCE_DIR="$(dirname "$BASH_SOURCE")/../resources/oled"
VENV_PYTHON="$VENV_DIR/bin/python3"

# 创建应用目录
log "  部署应用文件到: $OLED_APP_DIR"

if [[ -d "$OLED_APP_DIR" ]]; then
    log "  应用目录已存在，删除旧版本..."
    sudo rm -rf "$OLED_APP_DIR"
fi

if ! sudo -u "$USER_NAME" mkdir -p "$OLED_APP_DIR"; then
    error "无法创建 OLED 应用目录: $OLED_APP_DIR"
fi

# 复制应用文件
if ! sudo cp -r "$RESOURCE_DIR/." "$OLED_APP_DIR/"; then
    error "无法复制 OLED 资源文件"
fi

sudo chown -R "$USER_NAME:$USER_NAME" "$OLED_APP_DIR"
log "✓ 应用文件已部署"

# ✅ 使用模板系统安装服务（修复后）
log "  安装 systemd 用户服务..."

install_template_service \
    "oled.service" \
    "oled.service" \
    "true" \
    "USER_ID=$USER_ID" \
    "USER_RUNTIME_DIR=$USER_RUNTIME_DIR" \
    "OLED_APP_DIR=$OLED_APP_DIR" \
    "VENV_PYTHON=$VENV_PYTHON"

enable_linger
enable_user_service oled.service
start_user_service oled.service

# 验证服务状态
sleep 2
if user_service_status oled.service | grep -q "active"; then
    log "✓ OLED 服务运行中"
else
    warn "OLED 服务可能未正常启动
请检查: systemctl --user status oled
日志: journalctl --user -u oled -f"
fi

log "✓ OLED 显示屏安装完成"
