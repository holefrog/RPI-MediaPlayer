#!/usr/bin/env bash
# modules/05-oled.sh (修复版 - 使用 RPI_PLAYER_MAC)
# 注意：此模块由 stage_2.sh 通过 source 调用，环境已初始化
set -euo pipefail

# 定义模块名称（日志前缀）
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"

log "安装 OLED 显示屏..."

# ============================================
# 1. 读取配置与环境检查
# ============================================
# [修复] 添加参数空格
OLED_BUS=$(config_get_or_default "oled" "bus" "3")
OLED_ADDR=$(config_require "oled" "address")
OLED_WIDTH=$(config_require "oled" "width")
OLED_HEIGHT=$(config_require "oled" "height")

log "配置:  (${OLED_WIDTH}x${OLED_HEIGHT}) | Bus: $OLED_BUS | Addr: $OLED_ADDR"

# 硬件预检
I2C_DEV="/dev/i2c-${OLED_BUS}"
# [修复] 添加 [[ ]] 内部空格
if [[ ! -e "$I2C_DEV" ]]; then
    warn "警告: I2C 设备 $I2C_DEV 不存在。测试将跳过，服务可能无法启动。"
    warn "请检查 /boot/config.txt 是否开启了对应 I2C 总线 (dtparam=i2c_vc=on 等)。"
fi

# ============================================
# 2. 安装依赖与环境
# ============================================
log "安装系统依赖与 Python 环境..."

install_pkg python3 python3-pip python3-venv python3-smbus python3-pillow

VENV_DIR=$(get_oled_venv_dir)

# 仅当 venv 不存在或损坏时重建
# [修复] 添加 [[ ]] 内部空格
if [[ ! -f "$VENV_DIR/bin/python" ]]; then
    # [修复] 添加 [[ ]] 内部空格
    [[ -d "$VENV_DIR" ]] && sudo rm -rf "$VENV_DIR"
    # [修复] sudo -u user 命令间添加空格
    sudo -u "$USER_NAME" python3 -m venv "$VENV_DIR"
    log "Python 虚拟环境已创建"
fi

# 安装/升级 Python 库
# [修复] 添加空格
sudo -u "$USER_NAME" "$VENV_DIR/bin/pip" install --upgrade pip luma.oled requests >/dev/null 2>&1 || \
    error "Python 库安装失败"

# ============================================
# 3. 生成与运行测试脚本（修复审核建议 #5 - 强制测试通过）
# ============================================
log "生成并运行硬件测试..."

TARGET_SCRIPT="/usr/local/bin/oled_display.py"
TEST_TEMPLATE="${TEMPLATES_SCRIPTS_DIR}/oled_test.py.template"

# 3.1 生成测试脚本
# [修复] 参数间添加空格
install_template_file \
    "$TEST_TEMPLATE" \
    "$TARGET_SCRIPT" \
    "OLED_BUS=$OLED_BUS" \
    "OLED_ADDR=$OLED_ADDR" \
    "OLED_WIDTH=$OLED_WIDTH" \
    "OLED_HEIGHT=$OLED_HEIGHT"

sudo chmod 755 "$TARGET_SCRIPT"

# 3.2 运行测试（如果硬件存在则必须通过）
if [[ -e "$I2C_DEV" ]]; then
    # 🆕 从配置读取测试超时
    OLED_TEST_TIMEOUT=$(config_get_or_default "timeouts" "oled_test_timeout" "25")
    
    log "运行测试图案（显示 20 秒，超时 ${OLED_TEST_TIMEOUT}秒）..."
    
    # 使用 timeout 防止脚本卡死，使用虚拟环境 Python 运行
    if timeout "$OLED_TEST_TIMEOUT" sudo -u "$USER_NAME" "$VENV_DIR/bin/python" "$TARGET_SCRIPT" 2>&1; then
        log "✓ OLED 硬件测试通过"
    else
        # 修复审核建议 #5：硬件测试失败则中止安装
        error "OLED 硬件测试失败！请检查:
  1. I2C 接线是否正确（参见 HW_SSD1306.md）
  2. I2C 地址是否匹配: $OLED_ADDR
  3. 运行 'i2cdetect -y $OLED_BUS' 确认设备"
    fi
else
    log "跳过测试（I2C 设备不存在）"
fi

# ============================================
# 4. 部署应用
# ============================================
log "部署应用程序..."

OLED_APP_DIR=$(get_oled_app_dir)
RESOURCE_DIR="${RESOURCES_DIR}/oled"

# 准备目录
# [修复] 添加空格
if [[ -d "$OLED_APP_DIR" ]]; then
    sudo rm -rf "$OLED_APP_DIR"
fi
# [修复] 添加空格
sudo -u "$USER_NAME" mkdir -p "$OLED_APP_DIR"

# 复制文件
sudo cp "$RESOURCE_DIR"/*.py "$RESOURCE_DIR"/*.ttf "$OLED_APP_DIR/"
# [修复] 添加空格
sudo chown -R "$USER_NAME:$USER_NAME" "$OLED_APP_DIR"

# ============================================
# 5. 生成配置文件 (oled.ini)
# ============================================
# [修复] 添加空格
LMS_SERVER_IP=$(echo "$(config_require "squeezelite" "server")" | cut -d':' -f1)
LMS_SERVER_PORT=$(config_get_or_default "squeezelite" "port" "9000")
METADATA_PIPE=$(get_metadata_pipe)

# ✅ 修复：使用命名空间前缀变量 RPI_PLAYER_MAC
# 依赖检查：必须有 Player ID (MAC 地址)
if [[ -n "${RPI_PLAYER_MAC:-}" ]]; then
    PLAYER_ID="$RPI_PLAYER_MAC"
else
    error "缺少 RPI_PLAYER_MAC 变量。请确保 04-squeezelite.sh 模块已启用并成功运行。"
fi

# [修复] 添加空格
install_template_file \
    "${TEMPLATES_CONFIGS_DIR}/oled.ini.template" \
    "$OLED_APP_DIR/oled.ini" \
    "LMS_SERVER_IP=$LMS_SERVER_IP" \
    "LMS_SERVER_PORT=$LMS_SERVER_PORT" \
    "PLAYER_ID=$PLAYER_ID" \
    "OLED_BUS=$OLED_BUS" \
    "OLED_ADDR=$OLED_ADDR" \
    "OLED_WIDTH=$OLED_WIDTH" \
    "OLED_HEIGHT=$OLED_HEIGHT" \
    "METADATA_PIPE=$METADATA_PIPE"

# [修复] 添加空格
sudo chown "$USER_NAME:$USER_NAME" "$OLED_APP_DIR/oled.ini"

# ============================================
# 6. 安装并启动服务（使用统一函数）
# ============================================
log "6/7. 安装并启动 OLED 服务..."

VENV_PYTHON="${VENV_DIR}/bin/python3"

# [修复] 添加空格
install_template_service "oled.service" "oled.service" "true" \
    "USER_ID=$USER_ID" \
    "USER_RUNTIME_DIR=$USER_RUNTIME_DIR" \
    "OLED_APP_DIR=$OLED_APP_DIR" \
    "VENV_PYTHON=$VENV_PYTHON"

enable_user_service oled.service
start_user_service oled.service

# 使用统一的等待函数
wait_for_service oled.service user 10

# 验证服务状态（统一风格）
SERVICE_STATUS=$(check_service_status oled.service user)

# [修复] 添加空格，修复 == 两侧空格
if [[ "$SERVICE_STATUS" == "active" ]] || [[ "$SERVICE_STATUS" == "activating" ]]; then
    log "✓ OLED 模块安装完成且运行中"
else
    warn "OLED 服务状态: $SERVICE_STATUS"
    warn "参阅 TROUBLESHOOTING.md 获取帮助"
fi

log "✓ OLED 安装完成"
