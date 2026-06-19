#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"
MOBILE_DIR="$REPO_ROOT/mobile_app"
REQUIREMENTS_PATH="$BACKEND_DIR/requirements.txt"
VENV_DIR="$BACKEND_DIR/.venv"
VENV_PYTHON="$VENV_DIR/bin/python"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/.local/share/flutter}"
FLUTTER_BIN=""

print_step() {
  printf '\n==> %s\n' "$1"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_in_dir() {
  local working_dir="$1"
  shift
  (cd "$working_dir" && "$@")
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

install_flutter() {
  print_step "Instalando Flutter SDK local"

  command_exists git || die "git no esta instalado. Instala git y vuelve a ejecutar este script."

  mkdir -p "$(dirname "$FLUTTER_HOME")"
  if [[ -e "$FLUTTER_HOME" && -n "$(ls -A "$FLUTTER_HOME" 2>/dev/null)" ]]; then
    die "La ruta $FLUTTER_HOME existe pero no contiene un SDK Flutter usable. Revisala o define FLUTTER_HOME."
  fi

  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  export PATH="$FLUTTER_HOME/bin:$PATH"
  FLUTTER_BIN="$FLUTTER_HOME/bin/flutter"
}

parse_neo4j_endpoint() {
  local uri="${NEO4J_URI:-bolt://127.0.0.1:7687}"
  local without_scheme="$uri"
  if [[ "$without_scheme" == *"://"* ]]; then
    without_scheme="${without_scheme#*://}"
  fi

  local host_port="${without_scheme%%/*}"
  host_port="${host_port%%\?*}"

  local host="127.0.0.1"
  local port="7687"
  if [[ -n "$host_port" && "$host_port" == *":"* ]]; then
    host="${host_port%:*}"
    port="${host_port##*:}"
  elif [[ -n "$host_port" ]]; then
    host="$host_port"
  fi

  [[ -n "$host" ]] || host="127.0.0.1"
  [[ -n "$port" ]] || port="7687"
  printf '%s\t%s\t%s\n' "$uri" "$host" "$port"
}

test_tcp_port() {
  local host="$1"
  local port="$2"
  local timeout_seconds="${3:-2}"

  timeout "$timeout_seconds" bash -c ":</dev/tcp/$host/$port" >/dev/null 2>&1
}

check_neo4j() {
  print_step "Verificando Neo4j"

  local endpoint uri host port database
  endpoint="$(parse_neo4j_endpoint)"
  IFS=$'\t' read -r uri host port <<<"$endpoint"
  database="${NEO4J_DATABASE:-neo4j}"

  if test_tcp_port "$host" "$port" 2; then
    printf ' - Neo4j detectado en %s:%s\n' "$host" "$port"
    return 0
  fi

  printf '\nNEO4J NO ESTA INICIADO\n' >&2
  printf '\nNo se pudo conectar con Neo4j en %s:%s.\n' "$host" "$port" >&2
  printf 'Configuracion esperada: NEO4J_URI=%s, NEO4J_DATABASE=%s\n' "$uri" "$database" >&2
  printf '\nQue hacer en Ubuntu/Linux:\n' >&2
  printf '1. Inicia tu servicio o instancia local de Neo4j.\n' >&2
  printf '2. Verifica que Bolt escuche en 127.0.0.1:7687 o ajusta NEO4J_URI.\n' >&2
  printf '3. Si aun no lo tienes instalado, sigue la guia oficial: https://neo4j.com/docs/operations-manual/current/installation/linux/debian/\n' >&2
  printf '4. Vuelve a ejecutar este script.\n\n' >&2
  exit 20
}

[[ -d "$BACKEND_DIR" ]] || die "No se encontro la carpeta backend en: $BACKEND_DIR"
[[ -d "$MOBILE_DIR" ]] || die "No se encontro la carpeta mobile_app en: $MOBILE_DIR"
[[ -f "$REQUIREMENTS_PATH" ]] || die "No se encontro requirements.txt en: $REQUIREMENTS_PATH"

print_step "Configurando entorno backend"
command_exists python3 || die "python3 no esta instalado. Instala Python 3 y vuelve a ejecutar este script."

if [[ ! -x "$VENV_PYTHON" ]]; then
  python3 -m venv "$VENV_DIR"
fi

"$VENV_PYTHON" -m pip install --upgrade pip
"$VENV_PYTHON" -m pip install -r "$REQUIREMENTS_PATH"
"$VENV_PYTHON" -m pip check

print_step "Configurando Flutter"
if ! resolve_flutter; then
  install_flutter
fi

printf ' - Flutter detectado: %s\n' "$FLUTTER_BIN"
"$FLUTTER_BIN" --version
"$FLUTTER_BIN" config --enable-web

print_step "Instalando dependencias Flutter"
run_in_dir "$MOBILE_DIR" "$FLUTTER_BIN" pub get

check_neo4j

print_step "Setup Linux completo"
printf 'Backend venv: %s\n' "$VENV_DIR"
printf 'Flutter usado por los scripts: %s\n' "$FLUTTER_BIN"
if [[ "$FLUTTER_BIN" == "$FLUTTER_HOME/bin/flutter" ]]; then
  printf 'Para usar este Flutter en tu terminal: export PATH="%s/bin:$PATH"\n' "$FLUTTER_HOME"
fi
