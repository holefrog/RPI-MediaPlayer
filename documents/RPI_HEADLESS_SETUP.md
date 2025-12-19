# Raspberry Pi Headless Setup Guide

> **Important**  
> Previous versions of Raspberry Pi OS used a `wpa_supplicant.conf` file placed in the boot folder to configure wireless networks.  
> **This method is no longer supported starting with Raspberry Pi OS Bookworm (and later, including Trixie).**

---

## Step 1: Write microSD Card with Raspberry Pi Imager

1. **Launch Raspberry Pi Imager**  
   → Choose: **Raspberry Pi OS (Trixie)**

2. **Open Advanced Settings**  
   Press **`Ctrl + Shift + X`** to access pre-configuration:

   ### General
   - **Hostname**: `rpi.local`
   - **Username**: `player`
   - **Password**: `yourpassword`
   - **Configure wireless LAN** (enter SSID & password)
   - **Set locale settings** (timezone, keyboard, language)

   ### Services
   - [x] **Enable SSH**

3. **Write to microSD card**

---

## Step 2: Boot & Connect via SSH

1. Insert the microSD card into your Raspberry Pi and power it on.

2. Connect via SSH:
```bash
ssh player@rpi.local
```
   > (Ensure your computer is on the same network. `.local` uses mDNS.)

---

## Step 3: Add Shell Alias

```bash
nano ~/.bashrc
```

Add the following line at the end:
```bash
alias ll='ls -l'
```

Save & exit (`Ctrl+O` → `Enter` → `Ctrl+X`), then reload:
```bash
source ~/.bashrc
```

---

## Step 4: Update System

```bash
sudo apt-get update -y
sudo apt-get upgrade -y

sudo reboot
```

---

*Setup complete. Your Raspberry Pi is now accessible headlessly with updated software and useful aliases.*
