# 🔐 SSH 证书登录指南

本指南说明如何为 Raspberry Pi 设置基于 **SSH 密钥** 的免密码登录。

---

## 🗂️ 1. 创建目录和文件

```bash
mkdir -p ./rpi_keys
```

---

## 🪪 2. 生成密钥

```bash
ssh-keygen -t ed25519 -f ./rpi_keys/id_rpi -C "player@rpi"
```

> 生成过程中可直接连续按 **Enter** 使用默认选项。

---

## 📄 3. 获取公钥内容

打开生成的公钥文件：

```bash
cat ./rpi_keys/id_rpi.pub
```

复制其中的全部内容。

---

## 🧩 4. 在 Raspberry Pi Imager 中设置公钥

在 **Imager** 的设置项中找到：

```
Set authorized_keys for 'player':
```

将上一步复制的公钥内容粘贴进去。

---

## 💾 5. 保存公钥并烧录镜像

完成公钥粘贴后，点击 **保存设置**，然后继续执行 **烧录系统镜像** 到 SD 卡。  
烧录完成后即可将 SD 卡插入 Raspberry Pi。

---

## 💻 6. 登录到 Raspberry Pi

使用生成的私钥登录：

```bash
ssh -i ./rpi_keys/id_rpi player@rpi.local
```

---

## 📦 7. 备份与 PC 端使用

`./rpi_keys` 目录下包含：

- `id_rpi` → 私钥  
- `id_rpi.pub` → 公钥  

请妥善备份该目录。  
下次安装时可直接复制使用，无需重新生成。

### 🧰 Windows (PuTTY) 使用方法

1. 将 `id_rpi` 私钥文件传回电脑。  
2. 使用 **PuTTYgen.exe** 打开该文件并另存为 `id_rpi.ppk`。  
3. 在 **PuTTY** 中加载该 `.ppk` 文件即可使用密钥登录。

---

✅ 完成后，即可实现安全、免密码的 SSH 登录！
