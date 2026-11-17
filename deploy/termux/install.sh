#!/data/data/com.termux/files/usr/bin/bash
# Скачивает статические linux-arm64 бинарники Prometheus и Grafana в $MON_DATA/bin.
# Docker на телефоне не нужен: оба приложения — Go без cgo.
#
# Использование:
#   bash deploy/termux/install.sh
#   PROM_VER=3.16.0 GRAFANA_VER=12.2.0 bash deploy/termux/install.sh
set -euo pipefail

REPO="${MON_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
DATA="${MON_DATA:-$HOME/.monitoring}"
PROM_VER="${PROM_VER:-2.55.1}"      # как в docker-compose.yml репозитория
GRAFANA_VER="${GRAFANA_VER:-11.1.0}"  # как в docker-compose.yml (arhiv ~119 МБ)

ARCH="$(uname -m)"
if [ "$ARCH" != "aarch64" ]; then
  echo "ОШИБКА: скрипт для aarch64 (ARM64), сейчас: $ARCH" >&2
  exit 1
fi

command -v curl >/dev/null 2>&1 || pkg install -y curl
command -v tar  >/dev/null 2>&1 || pkg install -y tar

mkdir -p "$DATA/bin" "$DATA/data/prometheus" "$DATA/data/grafana" \
         "$DATA/logs" "$DATA/run" "$DATA/tmp"
cd "$DATA/tmp"

if [ -x "$DATA/bin/prometheus" ]; then
  echo "Prometheus уже установлен: $("$DATA/bin/prometheus" --version 2>&1 | head -1)"
else
  echo "==> Prometheus $PROM_VER"
  url="https://github.com/prometheus/prometheus/releases/download/v${PROM_VER}/prometheus-${PROM_VER}.linux-arm64.tar.gz"
  curl -fL --retry 3 -o prom.tar.gz "$url"
  dir="$(tar tzf prom.tar.gz | head -1 | cut -d/ -f1)"
  tar xzf prom.tar.gz
  cp -f "$dir/prometheus" "$DATA/bin/prometheus"; chmod 755 "$DATA/bin/prometheus"
  cp -f "$dir/promtool"   "$DATA/bin/promtool"   2>/dev/null && chmod 755 "$DATA/bin/promtool" || true
  mkdir -p "$DATA/bin/consoles" "$DATA/bin/console_libraries"
  cp -r "$dir/consoles/." "$DATA/bin/consoles/" 2>/dev/null || true
  cp -r "$dir/console_libraries/." "$DATA/bin/console_libraries/" 2>/dev/null || true
  echo "OK: $("$DATA/bin/prometheus" --version 2>&1 | head -1)"
fi

if [ -x "$DATA/bin/grafana" ]; then
  echo "Grafana уже установлена"
else
  echo "==> Grafana $GRAFANA_VER"
  url="https://dl.grafana.com/oss/release/grafana-${GRAFANA_VER}.linux-arm64.tar.gz"
  curl -fL --retry 3 -o grafana.tar.gz "$url"
  dir="$(tar tzf grafana.tar.gz | head -1 | cut -d/ -f1)"
  tar xzf grafana.tar.gz
  rm -rf "$DATA/grafana-dist"
  mv "$dir" "$DATA/grafana-dist"
  ln -sf "$DATA/grafana-dist/bin/grafana" "$DATA/bin/grafana"
  ln -sf "$DATA/grafana-dist/bin/grafana-server" "$DATA/bin/grafana-server" 2>/dev/null || true
  echo "OK: $("$DATA/bin/grafana" --version 2>&1 | head -1)"
fi

rm -rf "$DATA/tmp"
cat <<EOF

Готово. Репозиторий: $REPO
Бинарники:          $DATA/bin
Данные:             $DATA/data

Запуск:
  bash deploy/termux/start-prometheus.sh &
  GRAFANA_ADMIN_PASSWORD='свой-пароль' bash deploy/termux/start-grafana.sh &

С ноутбука (туннель):
  ssh -N -p 8022 -L 3000:127.0.0.1:3000 -L 9091:127.0.0.1:9091 u0_aXXX@<IP-телефона>
EOF
