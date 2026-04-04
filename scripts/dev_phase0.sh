#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
TS_PORT="${VOXLOG_TS_PORT:-7901}"
PY_PORT="${VOXLOG_PORT:-7902}"

if [ ! -x "$PYTHON_BIN" ]; then
  echo ".venv python not found at $PYTHON_BIN" >&2
  exit 1
fi

cleanup() {
  jobs -p | xargs -r kill 2>/dev/null || true
}

trap cleanup EXIT INT TERM

free_port() {
  local port="$1"
  local pids=""
  pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  if [ -n "$pids" ]; then
    echo "$pids" | xargs kill 2>/dev/null || true
    sleep 1
  fi
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-30}"
  for _ in $(seq 1 "$attempts"); do
    if curl -sf "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

free_port "$TS_PORT"
free_port "$PY_PORT"

(
  cd "$ROOT_DIR"
  VOXLOG_PORT="$PY_PORT" VOXLOG_API_TOKEN=dev-token "$PYTHON_BIN" -m apps.desktop.server
) &

(
  cd "$ROOT_DIR/services/api-ts"
  VOXLOG_TS_PORT="$TS_PORT" VOXLOG_PY_BACKEND_URL="http://127.0.0.1:${PY_PORT}" VOXLOG_PY_BACKEND_API_TOKEN=dev-token npm run dev
) &

wait_for_http "http://127.0.0.1:${PY_PORT}/health" 30
wait_for_http "http://127.0.0.1:${TS_PORT}/health" 30

cd "$ROOT_DIR/apps/desktop-tauri"
npm run dev
