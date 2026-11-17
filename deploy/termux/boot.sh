#!/data/data/com.termux/files/usr/bin/sh
# Автозапуск мониторинга после перезагрузки.
# Установить: cp deploy/termux/boot.sh ~/.termux/boot/monitoring.sh && chmod +x ~/.termux/boot/monitoring.sh
# Требуется Termux:Boot (F-Droid) и включённый автозапуск для Termux в MIUI.
termux-wake-lock
cd "$HOME/monitoring" || exit 1

# Туннели к VPS (если настроены) — до Prometheus, чтобы цели успели подняться
if [ -f "$HOME/.monitoring/tunnels.env" ]; then
  nohup bash deploy/termux/start-tunnels.sh >> "$HOME/.monitoring/logs/tunnels.log" 2>&1 &
  sleep 2
fi

nohup bash deploy/termux/start-prometheus.sh >> "$HOME/.monitoring/logs/prometheus.log" 2>&1 &
sleep 3
nohup bash deploy/termux/start-grafana.sh   >> "$HOME/.monitoring/logs/grafana.log"   2>&1 &
