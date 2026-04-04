#!/bin/bash
# Build self-contained VoxLog2.app — zero external dependencies
# Uses PyInstaller binary (no Python needed on target machine)
set -e

VOXLOG_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$VOXLOG_ROOT"

APP="$VOXLOG_ROOT/dist/VoxLog2.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "=== Building VoxLog2.app (zero-dependency) ==="

rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RESOURCES"

# Step 1: Build Swift UI
echo "[1/4] Building Swift UI..."
cd macos/VoxLogXcode
swift build -c release 2>&1 | grep -E "error|Build complete"
BIN=$(swift build -c release --show-bin-path 2>/dev/null)/VoxLog
cp "$BIN" "$MACOS_DIR/VoxLog2-ui"
cd "$VOXLOG_ROOT"

# Step 2: Build Python server binary (PyInstaller)
echo "[2/4] Building server binary..."
if [ ! -f dist/voxlog-server ]; then
    source .venv/bin/activate
    pyinstaller --onefile --name voxlog-server \
        --hidden-import uvicorn.logging \
        --hidden-import uvicorn.protocols.http \
        --hidden-import uvicorn.protocols.http.auto \
        --hidden-import uvicorn.protocols.http.h11_impl \
        --hidden-import uvicorn.protocols.websockets \
        --hidden-import uvicorn.protocols.websockets.auto \
        --hidden-import uvicorn.lifespan \
        --hidden-import uvicorn.lifespan.on \
        --hidden-import uvicorn.lifespan.off \
        --hidden-import core --hidden-import core.archive \
        --hidden-import core.asr_router --hidden-import core.audio \
        --hidden-import core.config --hidden-import core.dictionary \
        --hidden-import core.models --hidden-import core.polisher \
        --hidden-import core.network_detect --hidden-import core.stats \
        --hidden-import core.summarizer --hidden-import core.exporter \
        --hidden-import core.obsidian_sync --hidden-import server \
        --hidden-import server.app \
        --add-data "core:core" --add-data "server:server" \
        --add-data "terms.json:." \
        server_main.py 2>&1 | tail -3
fi
cp dist/voxlog-server "$MACOS_DIR/voxlog-server"

# Step 3: Create launcher
echo "[3/4] Creating launcher..."
cat > "$MACOS_DIR/VoxLog2" << 'LAUNCHER'
#!/bin/bash
DIR="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$HOME/.voxlog2/logs"

# Copy default terms.json
[ ! -f "$HOME/.voxlog2/terms.json" ] && cp "$DIR/Resources/terms.json" "$HOME/.voxlog2/terms.json" 2>/dev/null

# Create default .env if missing
[ ! -f "$HOME/.voxlog2/.env" ] && cat > "$HOME/.voxlog2/.env" << 'ENVEOF'
DASHSCOPE_API_KEY=
DASHSCOPE_REGION=us
OPENAI_API_KEY=
SILICONFLOW_API_KEY=
SILICONFLOW_BASE_URL=https://api.siliconflow.cn/v1
SILICONFLOW_MODEL=FunAudioLLM/SenseVoiceSmall
VOXLOG_API_TOKEN=voxlog2-dev-token
VOXLOG_ENV=home
ENVEOF

# Load API keys from .env into environment
if [ -f "$HOME/.voxlog2/.env" ]; then
    set -a
    source "$HOME/.voxlog2/.env"
    set +a
fi

# Check if server already running
if curl -s http://127.0.0.1:7902/health > /dev/null 2>&1; then
    SERVER_PID=""
else
    # Kill any stale process on port 7902
    lsof -ti :7902 2>/dev/null | xargs kill -9 2>/dev/null
    sleep 1

    # Start server
    "$DIR/MacOS/voxlog-server" > "$HOME/.voxlog2/logs/server.log" 2>&1 &
    SERVER_PID=$!

    for i in $(seq 1 15); do
        curl -s http://127.0.0.1:7902/health > /dev/null 2>&1 && break
        sleep 0.5
    done
fi

export VOXLOG_ROOT="$DIR/Resources"
"$DIR/MacOS/VoxLog2-ui"

[ -n "$SERVER_PID" ] && kill $SERVER_PID 2>/dev/null
LAUNCHER
chmod +x "$MACOS_DIR/VoxLog2"

# Copy resources
cp terms.json "$RESOURCES/"
[ -f macos/VoxLogXcode/AppIcon.icns ] && cp macos/VoxLogXcode/AppIcon.icns "$RESOURCES/"

# Step 4: Info.plist
echo "[4/4] Creating Info.plist..."
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>VoxLog2</string>
    <key>CFBundleIdentifier</key>
    <string>com.osborn.voxlog2</string>
    <key>CFBundleName</key>
    <string>VoxLog2</string>
    <key>CFBundleVersion</key>
    <string>0.3.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoxLog2 needs microphone access to record your voice for transcription.</string>
</dict>
</plist>
PLIST

APP_SIZE=$(du -sh "$APP" | awk '{print $1}')
echo ""
echo "=== VoxLog2.app v0.3.0 built ($APP_SIZE) ==="
echo "Zero Python dependency. Single binary server inside."
echo ""
echo "Install: cp -r $APP /Applications/"
echo "DMG:     hdiutil create -volname VoxLog2 -srcfolder /tmp/voxlog2-dmg -ov -format UDZO ~/Desktop/VoxLog2.dmg"
