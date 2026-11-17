#!/data/data/com.termux/files/usr/bin/bash
# Останавливает SSH-форварды, поднятые start-tunnels.sh.
set -euo pipefail
DATA="${MON_DATA:-$HOME/.monitoring}"
PID_FILE="$DATA/run/tunnels.pids"

if [ ! -f "$PID_FILE" ]; then
  echo "Нет $PID_FILE — туннели не запущены"
  exit 0
fi

while read -r pid port; do
  [ -n "${pid:-}" ] || continue
  # сначала убиваем сам ssh по уникальному порту, потом обёртку-рестартер
  pkill -f "127.0.0.1:${port}:" 2>/dev/null || true
  kill "$pid" 2>/dev/null || true
  echo "остановлен туннель на порту $port (wrapper pid $pid)"
done < "$PID_FILE"

rm -f "$PID_FILE"
echo "Готово"
