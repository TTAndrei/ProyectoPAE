#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"
MOBILE_DIR="$REPO_ROOT/mobile_app"
VENV_PYTHON="$BACKEND_DIR/.venv/bin/python"
STATE_PATH="$SCRIPT_DIR/.demo-state-linux.json"
LOG_DIR="$SCRIPT_DIR/.demo-logs"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/.local/share/flutter}"
FLUTTER_BIN=""
RUN_LOG=""

API_BASE_URL="http://localhost:8000"
BACKEND_PORT="8000"
FRONTEND_PORT="8081"
FORCE_RESTART=0
NO_LAUNCH=0
NO_CONSOLES=0

print_step() {
  if [[ -n "${RUN_LOG:-}" && -d "$(dirname "$RUN_LOG")" ]]; then
    printf '\n==> %s\n' "$1" | tee -a "$RUN_LOG"
  else
    printf '\n==> %s\n' "$1"
  fi
}

die() {
  if [[ -n "${RUN_LOG:-}" && -d "$(dirname "$RUN_LOG")" ]]; then
    printf '\nERROR: %s\n' "$*" | tee -a "$RUN_LOG" >&2
  else
    printf '\nERROR: %s\n' "$*" >&2
  fi
  exit 1
}

usage() {
  cat <<'USAGE'
Uso:
  bash scripts/start-demo-linux.sh [opciones]

Opciones:
  --api-base-url URL     URL de API para Flutter Web (defecto: http://localhost:8000)
  --backend-port PORT    Puerto backend FastAPI (defecto: 8000)
  --frontend-port PORT   Puerto servidor Flutter Web (defecto: 8081)
  --force-restart        Detiene la sesion Linux registrada antes de arrancar
  --no-launch            Arranca servicios sin abrir navegador con xdg-open
  --no-consoles          No abre terminales para seguir logs backend/frontend
  -h, --help             Muestra esta ayuda
USAGE
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

resolve_flutter() {
  if command_exists flutter; then
    FLUTTER_BIN="$(command -v flutter)"
    return 0
  fi

  if [[ -x "$FLUTTER_HOME/bin/flutter" ]]; then
    export PATH="$FLUTTER_HOME/bin:$PATH"
    FLUTTER_BIN="$FLUTTER_HOME/bin/flutter"
    return 0
  fi

  return 1
}

validate_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || die "Puerto no valido: $value"
  (( value >= 1 && value <= 65535 )) || die "Puerto fuera de rango: $value"
}

test_tcp_port() {
  local host="$1"
  local port="$2"
  local timeout_seconds="${3:-1}"

  timeout "$timeout_seconds" bash -c ":</dev/tcp/$host/$port" >/dev/null 2>&1
}

stop_process_group() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 0

  if kill -0 "$pid" >/dev/null 2>&1; then
    kill -TERM -- "-$pid" >/dev/null 2>&1 || kill -TERM "$pid" >/dev/null 2>&1 || true
    for _ in {1..30}; do
      if ! kill -0 "$pid" >/dev/null 2>&1; then
        return 0
      fi
      sleep 0.2
    done
    kill -KILL -- "-$pid" >/dev/null 2>&1 || kill -KILL "$pid" >/dev/null 2>&1 || true
  fi
}

open_log_terminal() {
  local title="$1"
  local log_path="$2"

  (( NO_CONSOLES == 0 )) || return 0

  local terminal=""
  for candidate in x-terminal-emulator gnome-terminal ptyxis konsole xfce4-terminal mate-terminal lxterminal xterm; do
    if command_exists "$candidate"; then
      terminal="$(command -v "$candidate")"
      break
    fi
  done

  if [[ -z "$terminal" ]]; then
    printf ' - No se encontro emulador de terminal. Log %s: %s\n' "$title" "$log_path" | tee -a "$RUN_LOG"
    return 0
  fi

  local terminal_name
  terminal_name="$(basename "$(readlink -f "$terminal" 2>/dev/null || printf '%s' "$terminal")")"
  local command_text
  command_text="printf '%s\n' '$title - $log_path'; tail -n +1 -f '$log_path'; exec bash"

  case "$terminal_name" in
    ptyxis)
      "$terminal" --new-window -T "$title" -- bash -lc "$command_text" >/dev/null 2>&1 &
      ;;
    gnome-terminal)
      "$terminal" --title="$title" -- bash -lc "$command_text" >/dev/null 2>&1 &
      ;;
    konsole)
      "$terminal" --new-tab --title "$title" -e bash -lc "$command_text" >/dev/null 2>&1 &
      ;;
    xfce4-terminal|mate-terminal|lxterminal)
      "$terminal" --title="$title" -e "bash -lc \"$command_text\"" >/dev/null 2>&1 &
      ;;
    *)
      "$terminal" -T "$title" -e bash -lc "$command_text" >/dev/null 2>&1 &
      ;;
  esac
}

wait_backend_ready() {
  local health_url="$1"
  local timeout_seconds="$2"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if "$VENV_PYTHON" - "$health_url" <<'PY' >/dev/null 2>&1; then
import json
import sys
import urllib.request

with urllib.request.urlopen(sys.argv[1], timeout=3) as response:
    payload = json.load(response)

raise SystemExit(0 if payload.get("status") == "ok" else 1)
PY
      return 0
    fi
    sleep 1
  done

  return 1
}

wait_http_ready() {
  local url="$1"
  local timeout_seconds="$2"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if "$VENV_PYTHON" - "$url" <<'PY' >/dev/null 2>&1; then
import sys
import urllib.request

with urllib.request.urlopen(sys.argv[1], timeout=3) as response:
    raise SystemExit(0 if 200 <= response.status < 500 else 1)
PY
      return 0
    fi
    sleep 1
  done

  return 1
}

write_state() {
  STATE_PATH_ENV="$STATE_PATH" \
  API_BASE_URL_ENV="$API_BASE_URL" \
  BACKEND_HEALTH_URL_ENV="$BACKEND_HEALTH_URL" \
  FRONTEND_URL_ENV="$FRONTEND_URL" \
  BACKEND_PID_ENV="$BACKEND_PID" \
  FRONTEND_PID_ENV="$FRONTEND_PID" \
  BACKEND_LOG_ENV="$BACKEND_LOG" \
  FRONTEND_LOG_ENV="$FRONTEND_LOG" \
  "$VENV_PYTHON" - <<'PY'
import json
import os
from datetime import datetime, timezone

state = {
    "started_at": datetime.now(timezone.utc).isoformat(),
    "api_base_url": os.environ["API_BASE_URL_ENV"],
    "backend_health_url": os.environ["BACKEND_HEALTH_URL_ENV"],
    "frontend_url": os.environ["FRONTEND_URL_ENV"],
    "backend_pid": int(os.environ["BACKEND_PID_ENV"]),
    "frontend_pid": int(os.environ["FRONTEND_PID_ENV"]),
    "backend_log": os.environ["BACKEND_LOG_ENV"],
    "frontend_log": os.environ["FRONTEND_LOG_ENV"],
}

with open(os.environ["STATE_PATH_ENV"], "w", encoding="utf-8") as state_file:
    json.dump(state, state_file, indent=2)
    state_file.write("\n")
PY
}

while (($#)); do
  case "$1" in
    --api-base-url)
      [[ $# -ge 2 ]] || die "Falta valor para --api-base-url"
      API_BASE_URL="$2"
      shift 2
      ;;
    --api-base-url=*)
      API_BASE_URL="${1#*=}"
      shift
      ;;
    --backend-port)
      [[ $# -ge 2 ]] || die "Falta valor para --backend-port"
      BACKEND_PORT="$2"
      shift 2
      ;;
    --backend-port=*)
      BACKEND_PORT="${1#*=}"
      shift
      ;;
    --frontend-port)
      [[ $# -ge 2 ]] || die "Falta valor para --frontend-port"
      FRONTEND_PORT="$2"
      shift 2
      ;;
    --frontend-port=*)
      FRONTEND_PORT="${1#*=}"
      shift
      ;;
    --force-restart)
      FORCE_RESTART=1
      shift
      ;;
    --no-launch)
      NO_LAUNCH=1
      shift
      ;;
    --no-consoles)
      NO_CONSOLES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Opcion no reconocida: $1"
      ;;
  esac
done

validate_port "$BACKEND_PORT"
validate_port "$FRONTEND_PORT"

BACKEND_HEALTH_URL="http://127.0.0.1:$BACKEND_PORT/health"
FRONTEND_URL="http://localhost:$FRONTEND_PORT"
WEB_BUILD_DIR="$MOBILE_DIR/build/web"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_LOG="$LOG_DIR/start-$TIMESTAMP.log"
BACKEND_LOG="$LOG_DIR/backend-$TIMESTAMP.log"
FRONTEND_LOG="$LOG_DIR/frontend-$TIMESTAMP.log"
BACKEND_PID=""
FRONTEND_PID=""

if [[ -f "$STATE_PATH" ]]; then
  if (( FORCE_RESTART )); then
    print_step "Deteniendo sesion Linux anterior"
    bash "$SCRIPT_DIR/stop-demo-linux.sh"
  else
    die "Ya existe una sesion Linux activa. Ejecuta scripts/stop-demo-linux.sh o relanza con --force-restart."
  fi
elif (( FORCE_RESTART )); then
  bash "$SCRIPT_DIR/stop-demo-linux.sh" >/dev/null 2>&1 || true
fi

print_step "Verificando dependencias Linux"
mkdir -p "$LOG_DIR"
printf 'Log de arranque: %s\n' "$RUN_LOG" | tee -a "$RUN_LOG"
bash "$SCRIPT_DIR/setup-linux.sh"

[[ -x "$VENV_PYTHON" ]] || die "No se encontro Python del entorno virtual en: $VENV_PYTHON"
resolve_flutter || die "Flutter no esta disponible despues del setup."

print_step "Compilando app Flutter Web"
(cd "$MOBILE_DIR" && "$FLUTTER_BIN" build web --no-wasm-dry-run "--dart-define=API_BASE_URL=$API_BASE_URL") 2>&1 | tee -a "$RUN_LOG"
[[ -f "$WEB_BUILD_DIR/index.html" ]] || die "No se encontro index.html en la build web: $WEB_BUILD_DIR"

if test_tcp_port 127.0.0.1 "$BACKEND_PORT" 1; then
  die "El puerto backend $BACKEND_PORT ya esta en uso. Deten el proceso o usa --backend-port."
fi
if test_tcp_port 127.0.0.1 "$FRONTEND_PORT" 1; then
  die "El puerto frontend $FRONTEND_PORT ya esta en uso. Deten el proceso o usa --frontend-port."
fi

print_step "Lanzando backend"
setsid bash -c 'cd "$1" && exec "$2" -m uvicorn app.main:aplicacion --reload --host 127.0.0.1 --port "$3"' \
  _ "$BACKEND_DIR" "$VENV_PYTHON" "$BACKEND_PORT" >"$BACKEND_LOG" 2>&1 &
BACKEND_PID=$!
printf ' - PID backend: %s\n' "$BACKEND_PID"
printf ' - Log backend: %s\n' "$BACKEND_LOG"
open_log_terminal "PAE Backend" "$BACKEND_LOG"

if ! wait_backend_ready "$BACKEND_HEALTH_URL" 45; then
  stop_process_group "$BACKEND_PID"
  die "El backend no respondio en $BACKEND_HEALTH_URL. Revisa el log: $BACKEND_LOG"
fi

print_step "Lanzando servidor Flutter Web"
setsid bash -c 'cd "$1" && exec "$2" -m http.server "$3" --bind 127.0.0.1' \
  _ "$WEB_BUILD_DIR" "$VENV_PYTHON" "$FRONTEND_PORT" >"$FRONTEND_LOG" 2>&1 &
FRONTEND_PID=$!
printf ' - PID frontend: %s\n' "$FRONTEND_PID"
printf ' - Log frontend: %s\n' "$FRONTEND_LOG"
open_log_terminal "PAE Flutter Web" "$FRONTEND_LOG"

if ! wait_http_ready "$FRONTEND_URL" 60; then
  stop_process_group "$BACKEND_PID"
  stop_process_group "$FRONTEND_PID"
  die "El frontend no respondio en $FRONTEND_URL. Revisa el log: $FRONTEND_LOG"
fi

write_state

if (( NO_LAUNCH )); then
  print_step "Demo Linux iniciada sin abrir navegador"
else
  print_step "Abriendo app en navegador"
  if command_exists xdg-open; then
    xdg-open "$FRONTEND_URL" >/dev/null 2>&1 &
  else
    printf ' - xdg-open no esta disponible. Abre manualmente: %s\n' "$FRONTEND_URL"
  fi
fi

printf '\nDemo Linux lista.\n'
printf 'API: %s\n' "$BACKEND_HEALTH_URL"
printf 'Frontend: %s\n' "$FRONTEND_URL"
printf 'Estado: %s\n' "$STATE_PATH"
printf 'Log de arranque: %s\n' "$RUN_LOG"
printf 'Para detener: bash scripts/stop-demo-linux.sh\n'
