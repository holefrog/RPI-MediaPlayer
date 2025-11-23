#!/usr/bin/env bash

# 如果不是 git 仓库则初始化
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git init
fi

# 设置远程（不管是否已存在，统一覆盖）
git remote remove origin 2>/dev/null
git remote add origin https://github.com/holefrog/RPI-MediaPlayer.git

# orphan 方式完全覆盖 main
git checkout --orphan temp_branch
git add .
git commit -m "Full overwrite"
git branch -M main

# 强制推送
git push origin main --force

