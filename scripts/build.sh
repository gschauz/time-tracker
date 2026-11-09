#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${TIME_TRACKER_BUILD_DIR:-$ROOT/../../work/swift-build}"
APP="$ROOT/../Time Tracker.app"
mkdir -p "$SCRATCH" "$APP/Contents/MacOS" "$APP/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$SCRATCH/module-cache"
swift build --disable-sandbox --cache-path "$SCRATCH/cache" --config-path "$SCRATCH/config" --security-path "$SCRATCH/security" --package-path "$ROOT" --scratch-path "$SCRATCH" -c release
BIN="$(swift build --disable-sandbox --cache-path "$SCRATCH/cache" --config-path "$SCRATCH/config" --security-path "$SCRATCH/security" --package-path "$ROOT" --scratch-path "$SCRATCH" -c release --show-bin-path)"
cp "$BIN/TimeTracker" "$APP/Contents/MacOS/.TimeTracker.new"
mv -f "$APP/Contents/MacOS/.TimeTracker.new" "$APP/Contents/MacOS/TimeTracker"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>TimeTracker</string>
  <key>CFBundleIdentifier</key><string>com.garret.timetracker</string>
  <key>CFBundleName</key><string>Time Tracker</string>
  <key>CFBundleDisplayName</key><string>Time Tracker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
swift "$ROOT/scripts/make-icon.swift" "$SCRATCH/AppIcon.iconset" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
