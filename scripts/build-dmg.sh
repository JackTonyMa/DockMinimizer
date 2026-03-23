#!/bin/bash

# DockMinimizer 打包脚本
# 用法: ./build-dmg.sh [版本号]

set -e

# 获取项目目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DMG_DIR="$PROJECT_DIR/dmg"

# 获取版本号
if [ -z "$1" ]; then
    VERSION=$(xcodebuild -project "$PROJECT_DIR/DockMinimizer.xcodeproj" -showBuildSettings 2>/dev/null | grep MARKETING_VERSION | tr -d ' ' | cut -d'=' -f2 | head -1)
    if [ -z "$VERSION" ]; then
        VERSION="1.0"
    fi
else
    VERSION="$1"
fi

echo "=========================================="
echo "DockMinimizer v$VERSION 打包脚本"
echo "=========================================="

# 清理旧的构建
echo "📦 清理旧构建..."
rm -rf /tmp/DockMinimizer-dmg
mkdir -p /tmp/DockMinimizer-dmg

# 构建 Release 版本
echo "🔨 构建 Release 版本 (通用二进制)..."
xcodebuild -project "$PROJECT_DIR/DockMinimizer.xcodeproj" \
    -scheme DockMinimizer \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    clean build \
    | xcpretty --simple 2>/dev/null || xcodebuild -project "$PROJECT_DIR/DockMinimizer.xcodeproj" \
    -scheme DockMinimizer \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    clean build

# 验证架构
echo "✅ 验证架构..."
ARCHS=$(lipo -archs "$HOME/Library/Developer/Xcode/DerivedData/DockMinimizer-"*/Build/Products/Release/DockMinimizer.app/Contents/MacOS/DockMinimizer 2>/dev/null | tail -1)
echo "   包含架构: $ARCHS"

# 复制 app 到临时目录
echo "📋 准备 DMG 内容..."
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/DockMinimizer-*/Build/Products/Release -name "DockMinimizer.app" -type d 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
    echo "❌ 找不到构建的 app"
    exit 1
fi
cp -R "$APP_PATH" /tmp/DockMinimizer-dmg/

# 创建 Applications 快捷方式
ln -s /Applications /tmp/DockMinimizer-dmg/Applications

# 创建 DMG
echo "💿 创建 DMG..."
mkdir -p "$DMG_DIR"
DMG_PATH="$DMG_DIR/DockMinimizer-$VERSION.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "DockMinimizer" \
    -srcfolder /tmp/DockMinimizer-dmg \
    -ov -format UDZO \
    "$DMG_PATH" \
    > /dev/null

# 清理临时文件
rm -rf /tmp/DockMinimizer-dmg

# 显示结果
DMG_SIZE=$(ls -lh "$DMG_PATH" | awk '{print $5}')
echo ""
echo "=========================================="
echo "✅ 打包完成!"
echo "=========================================="
echo "   文件: $DMG_PATH"
echo "   大小: $DMG_SIZE"
echo ""