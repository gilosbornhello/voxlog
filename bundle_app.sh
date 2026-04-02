#!/bin/bash
# Build a self-contained VoxLog.app that bundles Python + server inside
# No terminal needed — double click to run
set -e

VOXLOG_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$VOXLOG_ROOT"

APP="$VOXLOG_ROOT/dist/VoxLog.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
PYTHON_BUNDLE="$RESOURCES/python-env"

echo "=== Building self-contained VoxLog.app ==="

# Clean
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RESOURCES"

# Step 1: Build Swift binary
echo "[1/5] Building Swift..."
cd macos/VoxLogXcode
swift build -c release 2>&1 | grep -E "error|Build complete"
BIN=$(swift build -c release --show-bin-path 2>/dev/null)/VoxLog
cp "$BIN" "$MACOS_DIR/VoxLog-ui"
cd "$VOXLOG_ROOT"

# Step 2: Bundle Python venv (stripped down)
echo "[2/5] Bundling Python environment..."
if [ ! -d .venv ]; then
    echo "ERROR: .venv not found. Run: python3 -m venv .venv && pip install -e ."
    exit 1
fi

# Copy venv but skip unnecessary stuff
rsync -a --exclude='__pycache__' --exclude='*.pyc' --exclude='pip*' \
    --exclude='setuptools*' --exclude='pkg_resources*' --exclude='_distutils_hack*' \
    .venv/ "$PYTHON_BUNDLE/"

# Step 3: Bundle server code
echo "[3/5] Bundling server code..."
mkdir -p "$RESOURCES/voxlog"
cp -r core/ "$RESOURCES/voxlog/core/"
cp -r server/ "$RESOURCES/voxlog/server/"
cp terms.json "$RESOURCES/voxlog/"
cp pyproject.toml "$RESOURCES/voxlog/"

# Step 4: Create launcher script
echo "[4/5] Creating launcher..."
cat > "$MACOS_DIR/VoxLog" << 'LAUNCHER'
#!/bin/bash
DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="$DIR/Resources"
PYTHON="$RESOURCES/python-env/bin/python3"
SERVER_DIR="$RESOURCES/voxlog"

# Ensure ~/.voxlog exists
mkdir -p "$HOME/.voxlog/logs"

# Copy default terms.json if not exists
[ ! -f "$HOME/.voxlog/terms.json" ] && cp "$SERVER_DIR/terms.json" "$HOME/.voxlog/terms.json" 2>/dev/null

# Start Python server in background
export PYTHONPATH="$SERVER_DIR"
"$PYTHON" -m uvicorn server.app:app --host 127.0.0.1 --port 7890 --log-level info \
    > "$HOME/.voxlog/logs/server.log" 2>&1 &
SERVER_PID=$!

# Wait for server
for i in $(seq 1 15); do
    if curl -s http://127.0.0.1:7890/health > /dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

# Start UI
export VOXLOG_ROOT="$SERVER_DIR"
"$DIR/MacOS/VoxLog-ui"

# Cleanup on exit
kill $SERVER_PID 2>/dev/null
LAUNCHER
chmod +x "$MACOS_DIR/VoxLog"

# Step 5: Create Info.plist
echo "[5/5] Creating Info.plist..."
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VoxLog</string>
    <key>CFBundleIdentifier</key>
    <string>com.osborn.voxlog</string>
    <key>CFBundleName</key>
    <string>VoxLog</string>
    <key>CFBundleVersion</key>
    <string>0.2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoxLog needs microphone access to record your voice for transcription.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>VoxLog needs to paste text into your active application.</string>
</dict>
</plist>
PLIST

# Size report
APP_SIZE=$(du -sh "$APP" | awk '{print $1}')
echo ""
echo "=== VoxLog.app built: $APP ($APP_SIZE) ==="
echo ""
echo "Install:"
echo "  cp -r $APP /Applications/"
echo ""
echo "Then double-click VoxLog in Applications or Spotlight."
echo "No terminal needed. Server starts automatically inside the app."
