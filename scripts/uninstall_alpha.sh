#!/usr/bin/env bash

set -euo pipefail

APP_TARGET="/Applications/VoxLog.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
VOXLOG_HOME="$HOME/.voxlog"
BIN_DIR="$VOXLOG_HOME/bin"

launchctl unload "$LAUNCH_AGENTS_DIR/com.voxlog.backend.plist" >/dev/null 2>&1 || true
launchctl unload "$LAUNCH_AGENTS_DIR/com.voxlog.api-ts.plist" >/dev/null 2>&1 || true

rm -f "$LAUNCH_AGENTS_DIR/com.voxlog.backend.plist"
rm -f "$LAUNCH_AGENTS_DIR/com.voxlog.api-ts.plist"
rm -f "$BIN_DIR/start-backend.sh" "$BIN_DIR/start-api-ts.sh" "$BIN_DIR/start-gateway.sh"
rm -rf "$APP_TARGET"

echo "removed VoxLog alpha from /Applications and launch agents"
