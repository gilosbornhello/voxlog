#!/usr/bin/env bash

set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SOURCE="$BUNDLE_DIR/VoxLog.app"
RUNTIME_SOURCE="$BUNDLE_DIR/runtime-bundle"
TARGET_HOME="$HOME/.voxlog"
TARGET_RUNTIME="${VOXLOG_INSTALL_RUNTIME_DIR:-$TARGET_HOME/runtime-alpha}"
TARGET_APP="/Applications/VoxLog.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
BIN_DIR="$TARGET_HOME/bin"
ENV_FILE="$TARGET_HOME/.env"
SETTINGS_FILE="$TARGET_HOME/desktop-settings.json"
BACKEND_LOG="$TARGET_HOME/backend.log"
API_TS_LOG="$TARGET_HOME/api-ts.log"
GATEWAY_LOG="$TARGET_HOME/gateway.log"
API_TS_ENTRY_REL="services/api-ts/dist/services/api-ts/src/main.js"
DB_FILE="$TARGET_HOME/history-alpha.db"
BACKEND_BINARY_REL="bin/voxlog-backend"
GATEWAY_BINARY_REL="bin/voxlog-gateway"

require_command() {
  local command_name="$1"
  local hint="$2"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "missing dependency: $command_name" >&2
    echo "$hint" >&2
    exit 1
  fi
}

require_command rsync "rsync is required on macOS."
require_command curl "curl is required on macOS."

mkdir -p "$TARGET_HOME" "$BIN_DIR" "$LAUNCH_AGENTS_DIR"

if [ ! -d "$RUNTIME_SOURCE" ]; then
  echo "runtime bundle missing at $RUNTIME_SOURCE" >&2
  exit 1
fi

rsync -a --delete "$RUNTIME_SOURCE/" "$TARGET_RUNTIME/"

NODE_BIN="$TARGET_RUNTIME/bin/node"
if [ ! -x "$NODE_BIN" ]; then
  if command -v node >/dev/null 2>&1; then
    mkdir -p "$TARGET_RUNTIME/bin"
    cp "$(command -v node)" "$NODE_BIN"
    chmod +x "$NODE_BIN"
  else
    echo "bundled Node runtime missing and node is not installed" >&2
    exit 1
  fi
fi

if [ ! -f "$ENV_FILE" ] && [ -f "$TARGET_RUNTIME/.env.example" ]; then
  cp "$TARGET_RUNTIME/.env.example" "$ENV_FILE"
fi

if [ ! -f "$SETTINGS_FILE" ]; then
  cat > "$SETTINGS_FILE" <<JSON
{
  "backend_base_url": "http://127.0.0.1:7891",
  "active_profile": "home",
  "digest_enhancement_enabled": true,
  "digest_enhancement_provider": "auto",
  "obsidian_vault_dir": "",
  "ai_mate_memory_dir": "",
  "onboarding_completed": false,
  "hotkey_accelerator": "CommandOrControl+Shift+Space",
  "hotkey_enabled": false,
  "never_archive_apps": [
    "1password",
    "keychain access"
  ],
  "fast_path_only_apps": [
    "cursor",
    "claude"
  ],
  "disable_direct_typing_apps": [
    "terminal",
    "iterm",
    "warp"
  ]
}
JSON
fi

if [ ! -f "$TARGET_RUNTIME/$API_TS_ENTRY_REL" ]; then
  echo "api-ts dist bundle missing; rebuilding with bundled node" >&2
  if [ ! -d "$TARGET_RUNTIME/node_modules" ]; then
    echo "node_modules missing from runtime bundle" >&2
    exit 1
  fi
  (
    cd "$TARGET_RUNTIME"
    PATH="$TARGET_RUNTIME/node_modules/.bin:$PATH" "$NODE_BIN" ./node_modules/typescript/bin/tsc -p packages/contracts/tsconfig.json >/dev/null
    PATH="$TARGET_RUNTIME/node_modules/.bin:$PATH" "$NODE_BIN" ./node_modules/typescript/bin/tsc -p services/api-ts/tsconfig.json >/dev/null
  )
fi

BACKEND_COMMAND="\"\$ROOT_DIR/$BACKEND_BINARY_REL\""
GATEWAY_COMMAND="\"\$ROOT_DIR/$GATEWAY_BINARY_REL\""
if [ ! -x "$TARGET_RUNTIME/$BACKEND_BINARY_REL" ] || [ ! -x "$TARGET_RUNTIME/$GATEWAY_BINARY_REL" ]; then
  if command -v python3.11 >/dev/null 2>&1; then
    PYTHON_BIN="python3.11"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "missing backend runtime: bundled binaries not found and no Python available" >&2
    exit 1
  fi
  if [ ! -d "$TARGET_RUNTIME/.venv" ]; then
    "$PYTHON_BIN" -m venv "$TARGET_RUNTIME/.venv"
  fi
  "$TARGET_RUNTIME/.venv/bin/pip" install --upgrade pip >/dev/null
  "$TARGET_RUNTIME/.venv/bin/pip" install -e "$TARGET_RUNTIME" >/dev/null
  BACKEND_COMMAND="\"\$ROOT_DIR/.venv/bin/python\" -m apps.desktop.server"
  GATEWAY_COMMAND="\"\$ROOT_DIR/.venv/bin/python\" -m uvicorn apps.gateway.server:app --host 127.0.0.1 --port \"\${VOXLOG_GATEWAY_PORT:-7893}\""
fi

cat > "$BIN_DIR/start-backend.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$TARGET_RUNTIME"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ENV_FILE"
  set +a
fi
cd "\$ROOT_DIR"
export VOXLOG_PORT="\${VOXLOG_PORT:-7892}"
export VOXLOG_DB_PATH="$DB_FILE"
export VOXLOG_TERMS_DIR="\$ROOT_DIR/dictionaries"
export VOXLOG_API_TOKEN="\${VOXLOG_API_TOKEN:-voxlog-dev-token}"
$BACKEND_COMMAND
SH

cat > "$BIN_DIR/start-api-ts.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
wait_for_backend() {
  local url="\$1"
  local attempts="\${2:-45}"
  for _ in \$(seq 1 "\$attempts"); do
    if curl -sf "\$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}
ROOT_DIR="$TARGET_RUNTIME"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ENV_FILE"
  set +a
fi
PY_BACKEND_URL="\${VOXLOG_PY_BACKEND_URL:-http://127.0.0.1:7892}"
wait_for_backend "\${PY_BACKEND_URL}/health" 45
cd "\$ROOT_DIR/services/api-ts"
VOXLOG_TS_PORT="\${VOXLOG_TS_PORT:-7891}" \
VOXLOG_PY_BACKEND_URL="\$PY_BACKEND_URL" \
VOXLOG_PY_BACKEND_API_TOKEN="\${VOXLOG_PY_BACKEND_API_TOKEN:-\${VOXLOG_API_TOKEN:-voxlog-dev-token}}" \
"\$ROOT_DIR/bin/node" "\$ROOT_DIR/$API_TS_ENTRY_REL"
SH

cat > "$BIN_DIR/start-gateway.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$TARGET_RUNTIME"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ENV_FILE"
  set +a
fi
cd "\$ROOT_DIR"
export VOXLOG_GATEWAY_UPSTREAM_URL="\${VOXLOG_GATEWAY_UPSTREAM_URL:-http://127.0.0.1:7891}"
$GATEWAY_COMMAND
SH

chmod +x "$BIN_DIR/start-backend.sh" "$BIN_DIR/start-api-ts.sh" "$BIN_DIR/start-gateway.sh"

rm -rf "$TARGET_APP"
cp -R "$APP_SOURCE" "$TARGET_APP"

cat > "$LAUNCH_AGENTS_DIR/com.voxlog.backend.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.voxlog.backend</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN_DIR/start-backend.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>$TARGET_RUNTIME</string>
  <key>StandardOutPath</key>
  <string>$TARGET_HOME/backend.log</string>
  <key>StandardErrorPath</key>
  <string>$TARGET_HOME/backend.log</string>
</dict>
</plist>
PLIST

cat > "$LAUNCH_AGENTS_DIR/com.voxlog.api-ts.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.voxlog.api-ts</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN_DIR/start-api-ts.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>$TARGET_RUNTIME</string>
  <key>StandardOutPath</key>
  <string>$TARGET_HOME/api-ts.log</string>
  <key>StandardErrorPath</key>
  <string>$TARGET_HOME/api-ts.log</string>
</dict>
</plist>
PLIST

cat > "$LAUNCH_AGENTS_DIR/com.voxlog.gateway.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.voxlog.gateway</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN_DIR/start-gateway.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>$TARGET_RUNTIME</string>
  <key>StandardOutPath</key>
  <string>$GATEWAY_LOG</string>
  <key>StandardErrorPath</key>
  <string>$GATEWAY_LOG</string>
</dict>
</plist>
PLIST

launch_agent_reload() {
  local plist_path="$2"
  launchctl unload "$plist_path" >/dev/null 2>&1 || true
  launchctl load "$plist_path" >/dev/null 2>&1 || true
}

wait_for_health() {
  local name="$1"
  local url="$2"
  local log_file="$3"
  local attempts="${4:-60}"
  for _ in $(seq 1 "$attempts"); do
    if curl -sf "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "$name failed health check: $url" >&2
  if [ -f "$log_file" ]; then
    tail -n 60 "$log_file" >&2 || true
  fi
  return 1
}

health_ready() {
  local url="$1"
  curl -sf "$url" >/dev/null 2>&1
}

start_service_now() {
  local script_path="$2"
  local log_file="$3"
  pkill -f "$script_path" >/dev/null 2>&1 || true
  nohup "$script_path" >>"$log_file" 2>&1 &
}

: > "$BACKEND_LOG"
: > "$API_TS_LOG"
: > "$GATEWAY_LOG"

launch_agent_reload "com.voxlog.backend" "$LAUNCH_AGENTS_DIR/com.voxlog.backend.plist"
launch_agent_reload "com.voxlog.api-ts" "$LAUNCH_AGENTS_DIR/com.voxlog.api-ts.plist"
launch_agent_reload "com.voxlog.gateway" "$LAUNCH_AGENTS_DIR/com.voxlog.gateway.plist"

if ! health_ready "http://127.0.0.1:7892/health"; then
  start_service_now "backend" "$BIN_DIR/start-backend.sh" "$BACKEND_LOG"
fi
wait_for_health "backend" "http://127.0.0.1:7892/health" "$BACKEND_LOG" 60
if ! health_ready "http://127.0.0.1:7891/health"; then
  start_service_now "api-ts" "$BIN_DIR/start-api-ts.sh" "$API_TS_LOG"
fi
wait_for_health "api-ts" "http://127.0.0.1:7891/health" "$API_TS_LOG" 60
if ! health_ready "http://127.0.0.1:7893/health"; then
  start_service_now "gateway" "$BIN_DIR/start-gateway.sh" "$GATEWAY_LOG"
fi
wait_for_health "gateway" "http://127.0.0.1:7893/health" "$GATEWAY_LOG" 60

if [ "${VOXLOG_AUTO_OPEN_APP:-1}" = "1" ]; then
  open "$TARGET_APP"
fi

echo "installed VoxLog to $TARGET_APP"
echo "runtime installed to $TARGET_RUNTIME"
echo "env file: $ENV_FILE"
echo "settings file: $SETTINGS_FILE"
