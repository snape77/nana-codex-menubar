#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/nana-menu.app"
BIN="$APP/Contents/MacOS/nana-menu"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Install Xcode Command Line Tools first: xcode-select --install" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -parse-as-library \
  -O \
  -framework Cocoa \
  "$ROOT"/Sources/*.swift \
  -o "$BIN"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>nana-menu</string>
  <key>CFBundleIdentifier</key>
  <string>com.nana.codex.menubar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>nana menu</string>
  <key>CFBundleDisplayName</key>
  <string>nana menu</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>

  <!-- Menu-bar-only app: no Dock icon -->
  <key>LSUIElement</key>
  <true/>

  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built: $APP"

case "${1:-}" in
  --run)
    pkill -x nana-menu 2>/dev/null || true
    open -n "$APP"
    ;;
  --install)
    DEST="$HOME/Applications/nana-menu.app"
    mkdir -p "$HOME/Applications"
    pkill -x nana-menu 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open -n "$DEST"
    echo "Installed: $DEST"
    ;;
  "")
    ;;
  *)
    echo "Usage: $0 [--run|--install]" >&2
    exit 2
    ;;
esac
