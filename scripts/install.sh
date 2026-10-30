#!/bin/bash
#
# Transclase 一行安装脚本（macOS）
#
#   curl -fsSL https://raw.githubusercontent.com/JLZ0614/transclase/main/scripts/install.sh | bash
#
# 做三件事：下载最新 Release → 放进「应用程序」→ 去掉隔离标记。
# 想先看内容再运行，直接打开这个文件读一遍即可。

set -euo pipefail

REPO="JLZ0614/transclase"
VERSION="${TRANSCLASE_VERSION:-1.0.0}"
DEST="${TRANSCLASE_DEST:-/Applications}"
APP_NAME="Transclase.app"

say() { printf '\033[1m==>\033[0m %s\n' "$1"; }
die() { printf '\033[31m错误：\033[0m %s\n' "$1" >&2; exit 1; }

# --- 环境检查 ---------------------------------------------------------------
OS_VERSION="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VERSION%%.*}"
if [ "$OS_MAJOR" -lt 26 ]; then
  die "需要 macOS 26 或更高，当前是 $OS_VERSION。"
fi

if [ "$(uname -m)" != "arm64" ]; then
  say "注意：检测到 Intel Mac。App 可以运行，但实时识别需要 Apple Silicon，只能看演示模式。"
fi

URL="https://github.com/$REPO/releases/download/v$VERSION/Transclase-$VERSION-macOS.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 下载与解压 -------------------------------------------------------------
say "下载 Transclase $VERSION"
curl -fsSL "$URL" -o "$TMP/app.zip" || die "下载失败，检查网络或版本号（$URL）"

say "解压"
ditto -x -k "$TMP/app.zip" "$TMP/out" || die "解压失败"
APP_PATH="$(find "$TMP/out" -maxdepth 3 -name "$APP_NAME" -type d -print -quit)"
[ -n "$APP_PATH" ] || die "压缩包里没找到 $APP_NAME"

# 这一步是关键：去掉浏览器/系统打的隔离标记
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

# --- 安装 -------------------------------------------------------------------
say "安装到 $DEST"
mkdir -p "$DEST"
if [ -d "$DEST/$APP_NAME" ]; then
  rm -rf "$DEST/$APP_NAME" 2>/dev/null || sudo rm -rf "$DEST/$APP_NAME"
fi

if cp -R "$APP_PATH" "$DEST/" 2>/dev/null; then
  :
else
  say "需要管理员权限"
  sudo cp -R "$APP_PATH" "$DEST/"
fi
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || sudo xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

say "完成"
open "$DEST/$APP_NAME"
