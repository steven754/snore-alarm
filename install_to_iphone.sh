#!/usr/bin/env bash
# ============================================================
#  把「鼾声唤醒」装进你的 iPhone —— 一键准备脚本
#
#  用法（在终端里跑，会在 Rosetta 安装那一步要你的登录密码）：
#      bash ~/docker/snore-alarm/install_to_iphone.sh
#
#  脚本会做三件事：
#    1. 检查并安装 Rosetta 2（Sideloadly 是 x86_64 程序，Apple Silicon 上必须有它）
#    2. 检查 Sideloadly.app 是否就位
#    3. 用新 IPA 启动 Sideloadly，剩下的登录/安装你在界面里点
#
#  之后你只需要：
#    · 数据线连 iPhone，手机上点「信任此电脑」
#    · iPhone: 设置 → 隐私与安全性 → 开发者模式 → 打开（iOS 16+ 必须，会要求重启）
#    · 在 Sideloadly 窗口里拖入 IPA，填自己的 Apple ID，点 Start
#    · 手机上会要求输入该 Apple ID 的密码（Apple 官方验证）
# ============================================================

set -uo pipefail
cd "$(dirname "$0")"

IPA="$PWD/dist/snore-alarm-unsigned.ipa"
APP="/Applications/Sideloadly.app"

echo "=============================================="
echo "  鼾声唤醒 → iPhone 安装准备"
echo "=============================================="

# [1] Rosetta 2（Apple Silicon 上跑 x86_64 程序必需）
echo ""
echo "[1/3] 检查 Rosetta 2..."
if pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
  echo "  ✓ Rosetta 2 已安装"
else
  echo "  ✗ Rosetta 2 未安装 —— Sideloadly 是 x86_64 程序，Apple Silicon 上必须先装它"
  echo ""
  echo "  即将执行（需要你的登录密码）："
  echo "    sudo softwareupdate --install-rosetta --agree-to-license"
  echo ""
  sudo softwareupdate --install-rosetta --agree-to-license
  if pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    echo "  ✓ Rosetta 2 安装完成"
  else
    echo "  ✗ Rosetta 2 安装未成功，先解决这一步再继续"
    exit 1
  fi
fi

# [2] Sideloadly
echo ""
echo "[2/3] 检查 Sideloadly..."
if [ -d "$APP" ]; then
  echo "  ✓ 已安装：$APP"
else
  echo "  ✗ 未找到 Sideloadly.app"
  echo "    下载地址：https://sideloadly.io/  →  Download for macOS"
  exit 1
fi

# [3] IPA
echo ""
echo "[3/3] 检查安装包..."
if [ -f "$IPA" ]; then
  echo "  ✓ $IPA"
  echo "    大小：$(du -h "$IPA" | cut -f1)"
else
  echo "  ✗ 找不到 $IPA"
  echo "    可重新下载：cd $PWD && gh run download --repo steven754/snore-alarm --name snore-alarm-ipa"
  exit 1
fi

echo ""
echo "=============================================="
echo " ✅ 准备完成，正在启动 Sideloadly..."
echo "=============================================="
echo ""
echo "接下来："
echo "  1) 数据线连上 iPhone，手机上点「信任此电脑」"
echo "  2) iPhone: 设置 → 隐私与安全性 → 开发者模式 → 打开（会要求重启，iOS 16+ 必须）"
echo "  3) Sideloadly 窗口里把 IPA 拖进去，填你的 Apple ID（邮箱）+ 密码"
echo "  4) 选设备 → Start → 手机上输入该 Apple ID 的密码"
echo "  5) 装完打开「鼾声唤醒」，允许麦克风权限"
echo ""
echo "  免费 Apple ID 有效期 7 天，Sideloadly 会自动后台重签续期。"
echo "  装完记得把手机静音键拨到响铃位置（提示音在静音模式下不响）。"
echo ""

open -a "$APP" "$IPA"
