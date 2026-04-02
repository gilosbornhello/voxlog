#!/bin/bash
# VoxLog deployment script — run this on any Mac to set up VoxLog
# Usage: curl -sL <url> | bash   OR   bash deploy.sh
set -e

echo "==============================="
echo "  VoxLog Deployment"
echo "  Your mouth has a save button."
echo "==============================="
echo ""

VOXLOG_DIR="$HOME/voxlog"

# Step 1: Check prerequisites
echo "[1/7] Checking prerequisites..."

if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found. Install: brew install python@3.13"
    exit 1
fi

PY_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "  Python: $PY_VERSION"

if ! command -v swift &>/dev/null; then
    echo "ERROR: swift not found. Install Xcode: xcode-select --install"
    exit 1
fi
echo "  Swift: $(swift --version 2>&1 | head -1)"

if ! command -v ffmpeg &>/dev/null; then
    echo "  WARNING: ffmpeg not found (optional, needed for future Bot Gateway)"
fi

# Step 2: Check if voxlog directory exists
echo ""
echo "[2/7] Setting up project..."

if [ -d "$VOXLOG_DIR" ]; then
    echo "  Found existing $VOXLOG_DIR"
    cd "$VOXLOG_DIR"
    if [ -d .git ]; then
        echo "  Pulling latest..."
        git pull 2>/dev/null || echo "  (no remote configured, using local)"
    fi
else
    echo "  ERROR: $VOXLOG_DIR not found."
    echo "  Copy the voxlog directory from your other Mac first:"
    echo "    scp -r user@other-mac:~/voxlog ~/voxlog"
    echo "  Or git clone if you have a remote repo."
    exit 1
fi

# Step 3: Create venv and install dependencies
echo ""
echo "[3/7] Installing Python dependencies..."

if [ ! -d .venv ]; then
    python3 -m venv .venv
    echo "  Created virtual environment"
fi

source .venv/bin/activate
pip install --upgrade pip -q
pip install -e ".[dev]" -q 2>&1 | tail -3
echo "  Dependencies installed"

# Step 4: Configure API keys
echo ""
echo "[4/7] Configuring API keys..."

mkdir -p ~/.voxlog

if [ -f ~/.voxlog/.env ]; then
    echo "  Found existing ~/.voxlog/.env"
    awk -F= '{print "  "$1"=***"}' ~/.voxlog/.env
else
    cp .env.example ~/.voxlog/.env
    echo "  Created ~/.voxlog/.env from template"
    echo ""
    echo "  *** IMPORTANT: Edit ~/.voxlog/.env with your API keys ***"
    echo "  Required:"
    echo "    DASHSCOPE_API_KEY=sk-xxx    (Alibaba Qwen ASR)"
    echo "    OPENAI_API_KEY=sk-xxx       (OpenAI Whisper + GPT)"
    echo "  Optional:"
    echo "    SILICONFLOW_API_KEY=sk-xxx  (SenseVoice fallback for China)"
    echo ""
    read -p "  Edit now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} ~/.voxlog/.env
    fi
fi

# Step 5: Build macOS App
echo ""
echo "[5/7] Building VoxLog.app..."

cd macos/VoxLogXcode
swift build -c release 2>&1 | grep -E "error|Build complete" || true
BIN=$(swift build -c release --show-bin-path 2>/dev/null)/VoxLog

if [ ! -f "$BIN" ]; then
    echo "  ERROR: Build failed"
    exit 1
fi

# Create .app bundle
APP="$VOXLOG_DIR/build/VoxLog.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VoxLog"

cat > "$APP/Contents/Info.plist" << 'PLIST'
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
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoxLog needs microphone access to record your voice for transcription.</string>
</dict>
</plist>
PLIST

# Install to /Applications
rm -rf /Applications/VoxLog.app
cp -r "$APP" /Applications/VoxLog.app
echo "  VoxLog.app installed to /Applications/"

cd "$VOXLOG_DIR"

# Step 6: Set up auto-export cron
echo ""
echo "[6/7] Setting up Obsidian auto-export..."

mkdir -p ~/.voxlog/logs
mkdir -p ~/obsidian-vault/06-osborn/voice-logs 2>/dev/null || true

PLIST_PATH="$HOME/Library/LaunchAgents/com.voxlog.export.plist"
cat > "$PLIST_PATH" << LAUNCHD
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.voxlog.export</string>
    <key>ProgramArguments</key>
    <array>
        <string>$VOXLOG_DIR/.venv/bin/python</string>
        <string>$VOXLOG_DIR/export_cron.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$VOXLOG_DIR</string>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$HOME/.voxlog/logs/export.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.voxlog/logs/export.log</string>
</dict>
</plist>
LAUNCHD

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH" 2>/dev/null
echo "  Daily export to Obsidian at 2am"

# Step 7: Test
echo ""
echo "[7/7] Running tests..."

source .venv/bin/activate
RESULT=$(python -m pytest tests/ -q 2>&1 | tail -1)
echo "  $RESULT"

# Done
echo ""
echo "========================================"
echo "  VoxLog deployed successfully!"
echo "========================================"
echo ""
echo "  Start server:  cd ~/voxlog && source .venv/bin/activate && voxlog-server"
echo "  Open App:      open /Applications/VoxLog.app"
echo "  Web UI:        http://localhost:7890"
echo "  Quick start:   cd ~/voxlog && ./run.sh"
echo ""
echo "  First time: macOS will ask for Microphone + Accessibility permissions."
echo "  Grant both for VoxLog."
echo ""
echo "  Network auto-detection:"
echo "    US exit (home)  → Qwen ASR US + OpenAI Whisper"
echo "    China (office)  → Qwen ASR CN + SiliconFlow SenseVoice"
echo ""
