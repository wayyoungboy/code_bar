#!/bin/bash

set -e

echo "================================"
echo "   CodeBar 打包脚本"
echo "================================"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查 Xcode 是否安装
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}错误：未找到 Xcode 命令行工具${NC}"
    echo "请先安装 Xcode 或 Xcode Command Line Tools"
    exit 1
fi

# 检查项目文件
if [ ! -f "CodeBar.xcodeproj/project.pbxproj" ]; then
    echo -e "${RED}错误：未找到 Xcode 项目文件${NC}"
    echo "请确保在正确的目录运行此脚本"
    exit 1
fi

echo -e "${GREEN}✓ 环境检查通过${NC}"
echo ""

# 清理旧的构建
echo "🧹 清理旧的构建..."
rm -rf build/DerivedData
xcodebuild clean -project CodeBar.xcodeproj -scheme CodeBar > /dev/null 2>&1

# 构建 Release 版本
echo "🔨 构建 Release 版本..."
xcodebuild -project CodeBar.xcodeproj \
  -scheme CodeBar \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | grep -E "(Build succeeded|BUILD SUCCEEDED|error:|warning:)" || true

# 检查构建结果
if [ -d "build/Build/Products/Release/CodeBar.app" ]; then
    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}✓ 构建成功!${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo "📦 App 位置："
    echo "   $(pwd)/build/Build/Products/Release/CodeBar.app"
    echo ""
    echo "📂 打开构建目录？(y/n)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        open build/Build/Products/Release/
    fi
    echo ""
    echo "💡 提示："
    echo "   - 直接将 CodeBar.app 拖到 /Applications/ 即可使用"
    echo "   - 如果遇到\"无法验证开发者\"，在系统设置中允许即可"
    echo ""
else
    echo ""
    echo -e "${RED}================================${NC}"
    echo -e "${RED}✗ 构建失败${NC}"
    echo -e "${RED}================================${NC}"
    echo ""
    echo "请检查以下问题："
    echo "1. Xcode 是否已安装"
    echo "2. 是否已登录 Apple ID (Xcode → Settings → Accounts)"
    echo "3. 查看完整构建日志获取错误信息"
    echo ""

    # 尝试重新构建并显示错误
    xcodebuild -project CodeBar.xcodeproj \
      -scheme CodeBar \
      -configuration Release \
      -derivedDataPath build
    exit 1
fi
