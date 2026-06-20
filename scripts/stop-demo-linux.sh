#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"
VENV_PYTHON="$BACKEND_DIR/.venv/bin/python"
STATE_PATH="$SCRIPT_DIR/.demo-state-linux.json"

print_step() {
  printf '\n==> %s\n' "$1"
}

resolve_python() {
  if [[ -x "$VENV_PYTHON" ]]; then
    printf '%s\n' "$VENV_PYTHON"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi

  return 1
}

stop_process_group() {
  local pid="${1:-}"
  local label="${2:-proceso}"
  [[ -n "$pid" ]] || return 0

  if ! kill -0 "$pid" >/dev/null 2>&1; then
    printf ' - %s con PID %s ya no esta activo.\n' "$label" "$pid"
    return 0
  fi

  kill -TERM -- "-$pid" >/dev/null 2>&1 || kill -TERM "$pid" >/dev/null 2>&1 || true
  for _ in {1..30}; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      printf ' - %s detenido (PID %s).\n' "$label" "$pid"
      return 0
    fi
    sleep 0.2
  done

  kill -KILL -- "-$pid" >/dev/null 2>&1 || kill -KILL "$pid" >/dev/null 2>&1 || true
  printf ' - %s forzado (PID %s).\n' "$label" "$pid"
}

if [[ ! -f "$STATE_PATH" ]]; then
  printf 'No hay una sesion demo Linux registrada para detener.\n'
  exit 0
fi

PYTHON_BIN="$(resolve_python)" || {
  printf 'ERROR: No se encontro Python para leer el estado de la demo.\n' >&2
  exit 1
}

mapfile -t STATE_VALUES < <("$PYTHON_BIN" - "$STATE_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as state_file:
    state = json.load(state_file)

print(state.get("backend_pid", ""))
print(state.get("frontend_pid", ""))
print(state.get("backend_log", ""))
print(state.get("frontend_log", ""))
PY
)

BACKEND_PID="${STATE_VALUES[0]:-}"
FRONTEND_PID="${STATE_VALUES[1]:-}"
BACKEND_LOG="${STATE_VALUES[2]:-}"
FRONTEND_LOG="${STATE_VALUES[3]:-}"

print_step "Deteniendo demo Linux"
stop_process_group "$FRONTEND_PID" "frontend"
stop_process_group "$BACKEND_PID" "backend"

rm -f "$STATE_PATH"

printf '\nSesion demo Linux detenida y estado limpiado.\n'
if [[ -n "$BACKEND_LOG" || -n "$FRONTEND_LOG" ]]; then
  printf 'Logs conservados para diagnostico:\n'
  [[ -n "$BACKEND_LOG" ]] && printf ' - %s\n' "$BACKEND_LOG"
  [[ -n "$FRONTEND_LOG" ]] && printf ' - %s\n' "$FRONTEND_LOG"
fi
