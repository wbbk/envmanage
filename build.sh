#!/bin/bash
# EnvManage 构建脚本：编译 SwiftUI 原生应用并打包为 EnvManage.app / .dmg
#
# 用法:  bash build.sh
# 产物:  dist/EnvManage.app   dist/EnvManage.dmg
#
# 依赖:  仅 macOS 自带工具链（swiftc / iconutil / codesign / hdiutil），无第三方。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP="EnvManage"
DIST="$ROOT/dist"
BUILD="$ROOT/.build"
APPDIR="$DIST/$APP.app"
CONTENTS="$APPDIR/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
ARCH="$(uname -m)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="${ARCH}-apple-macosx13.0"

echo "[1/6] 清理…"
rm -rf "$APPDIR"
mkdir -p "$MACOS" "$RES" "$BUILD"

echo "[2/6] 生成应用图标…"
if command -v iconutil >/dev/null 2>&1; then
  rm -rf "$ROOT/Resources/AppIcon.iconset"
  swift "$ROOT/Scripts/make_icon.swift" "$ROOT/Resources/AppIcon.iconset" >/dev/null 2>&1 || true
  if [ -d "$ROOT/Resources/AppIcon.iconset" ]; then
    iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$RES/AppIcon.icns" 2>/dev/null || true
  fi
fi
[ -f "$RES/AppIcon.icns" ] || echo "  (跳过图标：iconutil 不可用)"

echo "[3/6] 编译 Swift 源码…"
SOURCES=$(find "$ROOT/Sources" -name '*.swift' | sort)
# shellcheck disable=SC2086
swiftc -O -parse-as-library \
  -target "$TARGET" -sdk "$SDK" \
  -framework SwiftUI -framework AppKit \
  -o "$MACOS/$APP" $SOURCES

echo "[4/6] 写入 Info.plist / PkgInfo…"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>EnvManage</string>
    <key>CFBundleDisplayName</key>     <string>EnvManage</string>
    <key>CFBundleIdentifier</key>      <string>com.envmanage.app</string>
    <key>CFBundleExecutable</key>      <string>EnvManage</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key> <string>© 2026 EnvManage</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "[5/6] 本地 ad-hoc 签名…"
codesign --force --deep --sign - "$APPDIR" 2>/dev/null || echo "  (codesign 跳过)"

echo "[6/6] 打包 DMG…"
DMG="$DIST/$APP.dmg"
rm -f "$DMG"
STAGE="$DIST/dmgstage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APPDIR" "$STAGE/"
ln -sf /Applications "$STAGE/Applications" 2>/dev/null || true
hdiutil create -quiet -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" 2>/dev/null || {
  echo "  (hdiutil 失败，跳过 DMG)"; rm -f "$DMG"; }
rm -rf "$STAGE"

echo ""
echo "✅ 构建完成："
echo "   App : $APPDIR"
[ -f "$DMG" ] && echo "   DMG : $DMG"
echo ""
echo "运行： open \"$APPDIR\""
