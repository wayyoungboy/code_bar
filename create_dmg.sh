#!/bin/bash

set -e

echo "================================"
echo "   CodeBar DMG 打包工具"
echo "================================"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否传入了 APP 路径参数
APP_PATH="${1:-build/Build/Products/Release/CodeBar.app}"
APP_NAME="CodeBar"
DMG_NAME="CodeBar.dmg"
VOLUME_NAME="CodeBar Installer"
DMG_BACKGROUND_IMG="dmg_background.png"

# 检查 app 是否存在
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}错误：未找到 $APP_PATH${NC}"
    echo "请先运行 ./build.sh 构建应用"
    exit 1
fi

echo -e "${GREEN}✓ 找到应用：$APP_PATH${NC}"
echo ""

# 删除旧的 DMG 文件（如果存在）
if [ -f "$DMG_NAME" ]; then
    echo "🗑️  删除旧的 DMG 文件..."
    rm -f "$DMG_NAME"
fi

# 创建临时目录
TEMP_DIR=$(mktemp -d)
DMG_DIR="$TEMP_DIR/DMG_DIR"
mkdir -p "$DMG_DIR"

# 复制 App 到临时目录
echo "📦 复制应用文件..."
cp -R "$APP_PATH" "$DMG_DIR/"

# 创建 Applications 快捷方式
echo "🔗 创建 Applications 快捷方式..."
ln -s /Applications "$DMG_DIR/Applications"

# 创建背景图片目录
mkdir -p "$DMG_DIR/.background"

# 创建简单的背景图片（使用纯色）
# 如果有 create-dmg 工具，可以使用更专业的背景
if command -v create-dmg &> /dev/null; then
    echo -e "${GREEN}✓ 检测到 create-dmg 工具${NC}"
    echo "使用 create-dmg 创建专业 DMG..."

    # 清理临时 DMG 目录
    rm -rf "$TEMP_DIR"

    create-dmg \
        --volname "$VOLUME_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "CodeBar.app" 150 180 \
        --hide-extension "CodeBar.app" \
        --app-drop-link 450 180 \
        --no-internet-enable \
        "$DMG_NAME" \
        "$APP_PATH"

    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}✓ DMG 创建成功!${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo "📦 DMG 位置：$(pwd)/$DMG_NAME"
    echo ""
    echo "💡 使用方法："
    echo "   1. 双击打开 $DMG_NAME"
    echo "   2. 将 CodeBar 拖到 Applications 文件夹"
    echo ""
    exit 0
fi

# 不使用 create-dmg 时，使用 hdiutil 创建基础 DMG
echo "📝 使用 hdiutil 创建 DMG..."

# 创建临时镜像文件
TEMP_DMG="$TEMP_DIR/temp.dmg"
hdiutil create -size 50m \
    -volname "$VOLUME_NAME" \
    -fs "HFS+" \
    -layout SPUD \
    "$TEMP_DMG"

# 挂载镜像
echo "🔧 挂载镜像..."
MOUNT_DIR="/Volumes/$VOLUME_NAME"
# 卸载已存在的同名卷
hdiutil detach "$MOUNT_DIR" 2>/dev/null || true

MOUNT_OUTPUT=$(hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR" 2>&1)
MOUNT_DEVICE=$(echo "$MOUNT_OUTPUT" | grep "^/dev/" | head -1 | awk '{print $1}')

# 复制文件到挂载的卷
echo "📁 复制文件到镜像..."
cp -R "$APP_PATH" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

# 设置背景（如果有背景图片）
# 这里使用简单的纯色背景，可以通过设置 .DS_Store 来定制
# 由于 .DS_Store 是二进制文件，这里不做复杂设置

# 卸载镜像
echo "💿 完成镜像创建..."
hdiutil detach "$MOUNT_DEVICE" 2>/dev/null || true
sleep 2

# 转换为只读的压缩 DMG
echo "🔒 创建只读压缩 DMG..."
hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_NAME"

# 清理临时文件
rm -rf "$TEMP_DIR"

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}✓ DMG 创建成功!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "📦 DMG 位置：$(pwd)/$DMG_NAME"
echo ""
echo "💡 使用方法："
echo "   1. 双击打开 $DMG_NAME"
echo "   2. 将 CodeBar 拖到 Applications 文件夹"
echo ""
echo "📤 上传到 GitHub Release:"
echo "   gh release create v1.0.0 $DMG_NAME --title 'CodeBar v1.0.0'"
echo ""
