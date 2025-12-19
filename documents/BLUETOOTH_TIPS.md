# RPI-MediaPlayer 蓝牙自动配对策略

本文档总结了为 **RPI-MediaPlayer** 项目设计的蓝牙 A2DP（音频播放）自动配对策略，目标是打造一个“傻瓜级”的无缝蓝牙体验。

## 1. 目标

实现一个真正的“即连即用”蓝牙音频接收器。用户（iPhone / Android）无需任何额外操作，只需：

- 连接
- 断开
- “忘记此设备”后重新连接

整个流程始终不会出现 **“配对失败”** 或 **“PIN 码不正确”** 等报错。

## 2. 核心问题：单边失忆（One-Sided Amnesia）

标准 BlueZ（Linux 蓝牙协议栈）在处理“重新配对”时存在一个典型的用户体验问题。

### 典型流程

1. **成功配对**
 手机（如 iPhone）与 RPI 配对成功，双方都保存一个 Link Key。

2. **手机端忘记设备**
 用户点击 iPhone 的“忘记此设备”，手机会删除本地密钥。

3. **RPI 没有忘记**
 RPI 的数据库（`/var/lib/bluetooth/...`）仍保存旧的 MAC 地址和旧密钥。

4. **重新配对失败**
 - iPhone 发起新的配对请求
 - BlueZ 认为该 MAC 地址是“已配对设备”，期待对方使用旧密钥进行**重连**
 - 实际上手机发来的是新的配对请求
 - BlueZ 误以为是中间人攻击，从而拒绝请求
 - 用户看到错误：“配对不成功 / PIN 码不正确”

## 3. 解决方案：双保险策略

我们采用“**安装时硬修复 + 运行时软管理**”的双保险方案，从根本上彻底解决单边失忆问题。

- **阶段一：硬修复** — 在安装阶段执行（`08-bluetooth.sh`）
- **阶段二：软管理** — 系统运行时持续维护（`bluetooth-a2dp-autopair.sh`）

## 4. 阶段一：安装时“硬修复”（08-bluetooth.sh）

安装期间，我们对 BlueZ 服务进行了永久性的优化配置，包括策略修复、缓存清理和代理设置。

### 4.1 修改 main.conf：蓝牙核心策略补丁

在 `/etc/bluetooth/main.conf` 中应用以下配置：

```ini
[General]
JustWorksRepairing = always
AlwaysPairable = true
DiscoverableTimeout = 0
Class = 0x240414
```

### 4.2 清理物理缓存

```bash
sudo find /var/lib/bluetooth -type f -name "cache" -delete
sudo find /var/lib/bluetooth -type d -name "[0-9A-F][0-9A-F]:*" -exec rm -rf {} +
```

### 4.3 自动接受代理组合拳

- 设置默认代理（NoInputNoOutput）
- 配置 `pins.txt` 通配规则
- 运行 bt-agent 自动批准所有配对请求

## 5. 阶段二：运行时“软管理”（bluetooth-a2dp-autopair.sh）

系统运行期间后台服务自动提供保险机制，包括：

- 连接时关闭可发现性
- 断开时移除所有已配对设备（主动失忆）
- 始终保持数据库干净，避免配对失败

## 6. 手动管理模式

| 命令 | 功能 |
|------|------|
| `status` | 查看服务状态与已配对设备 |
| `clear` | 手动触发逻辑清理 |
| `reset` | 停止服务 → 删除缓存 → 重启（硬重置） |

## 7. 总结：三层防御体系

### ① 代理层（bt-agent + pins.txt）
负责自动批准免 PIN 配对。

### ② 核心层（main.conf）
负责处理重新配对与策略修复。

### ③ 服务层（autopair.sh）
负责运行时自动清理，确保所有连接都是最简单的首次配对流程。
