#!/data/data/com.termux/files/usr/bin/bash
# Поднимает SSH-форварды с телефона до VPS, чтобы Prometheus на телефоне
# скрапил /metrics ботов через 127.0.0.1. Наружу на VPS ничего не публикуется:
# порты ботов остаются loopback, трафик идёт внутри SSH.
#
# Конфиг: ~/.monitoring/tunnels.env (пример — deploy/termux/tunnels.env.example)
set -euo pipefail

REPO="${MON_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
DATA="${MON_DATA:-$HOME/.monitoring}"
ENV_FILE="${MON_TUNNELS_ENV:-$DATA/tunnels.env}"

[ -f "$ENV_FILE" ] || { echo "Нет $ENV_FILE — скопируй deploy/termux/tunnels.env.example" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

: "${VPS_HOST:?VPS_HOST не задан в $ENV_FILE}"
VPS_PORT="${VPS_PORT:-22}"
PORTS="${TUNNEL_PORTS:-}"

[ -n "$PORTS" ] || { echo "TUNNEL_PORTS пуст в $ENV_FILE" >&2; exit 1; }

mkdir -p "$DATA/logs" "$DATA/run"
PID_FILE="$DATA/run/tunnels.pids"
: > "$PID_FILE"

start_one() {
  local local_port="$1" remote_port="$2"
  local log="$DATA/logs/tunnel-$local_port.log"
  nohup bash -c '
    lp="$1"; rp="$2"; port="$3"; host="$4"; log="$5"
    while true; do
      ssh -N -p "$port" \
          -o ExitOnForwardFailure=yes \
          -o ServerAliveInterval=30 \
          -o ServerAliveCountMax=3 \
          -o StrictHostKeyChecking=accept-new \
          -L "127.0.0.1:$lp:127.0.0.1:$rp" "$host"
      echo "[$(date)] туннель $lp->$rp оборвался, рестарт через 5с" >> "$log"
      sleep 5
    done
  ' _ "$local_port" "$remote_port" "$VPS_PORT" "$VPS_HOST" "$log" >> "$log" 2>&1 &
  local pid=$!
  echo "$pid $local_port" >> "$PID_FILE"
  echo "туннель 127.0.0.1:$local_port -> $VPS_HOST:127.0.0.1:$remote_port  (pid $pid, лог $log)"
}

for p in $PORTS; do
  case "$p" in
    *:*) start_one "${p%%:*}" "${p##*:}" ;;
    *)   start_one "$p" "$p" ;;
  esac
done

echo "Готово. Проверка: curl -fsS http://127.0.0.1:<порт>/metrics | head"
echo "Остановить: bash deploy/termux/stop-tunnels.sh"
