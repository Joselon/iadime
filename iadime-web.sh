#!/bin/sh

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PID_FILE="$ROOT_DIR/tmp/iadime-web.pid"
LOG_DIR="$ROOT_DIR/logs"
LOG_FILE="$LOG_DIR/iadime-web.log"
HOST_VALUE=${HOST:-127.0.0.1}
PORT_VALUE=${PORT:-8080}

mkdir -p "$ROOT_DIR/tmp"
mkdir -p "$LOG_DIR"

is_running() {
  if [ ! -f "$PID_FILE" ]; then
    return 1
  fi

  PID=$(cat "$PID_FILE")
  if [ -z "$PID" ]; then
    return 1
  fi

  if kill -0 "$PID" 2>/dev/null; then
    return 0
  fi

  rm -f "$PID_FILE"
  return 1
}

start_server() {
  if is_running; then
    echo "[!] iadime-web ya está en ejecución (PID: $(cat "$PID_FILE"))"
    exit 1
  fi

  echo "[+] Iniciando iadime-web en http://$HOST_VALUE:$PORT_VALUE"
  HOST="$HOST_VALUE" PORT="$PORT_VALUE" python3 "$ROOT_DIR/server.py" >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  echo "[OK] Servidor iniciado con PID $(cat "$PID_FILE")"
}

stop_server() {
  if ! is_running; then
    echo "[-] iadime-web no está en ejecución"
    exit 0
  fi

  PID=$(cat "$PID_FILE")
  echo "[+] Deteniendo iadime-web (PID: $PID)"
  kill "$PID" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo "[OK] Solicitud de parada enviada"
}

status_server() {
  if is_running; then
    echo "[STATUS] Ejecutando (PID: $(cat "$PID_FILE")) en http://$HOST_VALUE:$PORT_VALUE"
  else
    echo "[STATUS] Detenido"
  fi
}

restart_server() {
  stop_server
  start_server
}

case "$1" in
  start)
    start_server
    ;;
  stop)
    stop_server
    ;;
  restart)
    restart_server
    ;;
  status)
    status_server
    ;;
  *)
    echo "Uso: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
