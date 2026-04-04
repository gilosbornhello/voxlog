#!/bin/bash
# Build VoxLog2.app — a proper macOS .app bundle
# This solves the permissions problem: macOS can recognize and authorize a .app
set -e

VOXLOG_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$VOXLOG_ROOT/build"
APP_DIR="$BUILD_DIR/VoxLog2.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building VoxLog2.app..."

# Clean
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES"

# Build Swift binary
cd "$VOXLOG_ROOT/macos/VoxLog"
swift build -c release 2>/dev/null
BINARY=$(swift build -c release --show-bin-path 2>/dev/null)/VoxLog
cp "$BINARY" "$MACOS_DIR/VoxLog2"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VoxLog2</string>
    <key>CFBundleIdentifier</key>
    <string>com.osborn.voxlog2</string>
    <key>CFBundleName</key>
    <string>VoxLog2</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoxLog2 needs microphone access to record your voice for transcription.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>VoxLog2 needs to paste text into your active application.</string>
</dict>
</plist>
PLIST

# Create launcher script that sets VOXLOG_ROOT
cat > "$MACOS_DIR/VoxLog2-launcher" << LAUNCHER
#!/bin/bash
export VOXLOG_ROOT="$VOXLOG_ROOT"
exec "\$(dirname "\$0")/VoxLog2"
LAUNCHER
chmod +x "$MACOS_DIR/VoxLog2-launcher"

# Update Info.plist to use launcher
sed -i '' 's|<string>VoxLog2</string>|<string>VoxLog2-launcher</string>|' "$CONTENTS/Info.plist"
# Only replace the first occurrence (CFBundleExecutable)
# Actually let's just set it correctly
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VoxLog2-launcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.osborn.voxlog2</string>
    <key>CFBundleName</key>
    <string>VoxLog2</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoxLog2 needs microphone access to record your voice for transcription.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>VoxLog2 needs to paste text into your active application.</string>
</dict>
</plist>
PLIST

echo ""
echo "Built: $APP_DIR"

# Auto-install to /Applications/
echo "Installing to /Applications/..."
rm -rf /Applications/VoxLog2.app
cp -r "$APP_DIR" /Applications/VoxLog2.app

echo ""
echo "=== VoxLog2.app installed ==="
echo ""
echo "Launch: open /Applications/VoxLog2.app"
echo "   or: Spotlight → VoxLog2"
echo ""
echo "First launch: macOS will ask for Accessibility + Microphone permissions."
echo "Click 'Grant Permissions' in the menu bar dropdown."
echo ""
echo "Usage: Hold Left Alt to record, release to paste."
