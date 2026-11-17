#!/data/data/com.termux/files/usr/bin/bash
# Prometheus для Termux: слушает ТОЛЬКО 127.0.0.1:9091.
# Конфиг генерируется из prometheus.yml.tmpl с подстановкой путей.
set -euo pipefail

REPO="${MON_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
DATA="${MON_DATA:-$HOME/.monitoring}"
LISTEN="${PROM_LISTEN:-127.0.0.1:9091}"
RETENTION="${PROM_RETENTION:-14d}"

[ -x "$DATA/bin/prometheus" ] || { echo "Нет $DATA/bin/prometheus — сначала bash deploy/termux/install.sh" >&2; exit 1; }
[ -d "$REPO/prometheus/targets" ] || { echo "Нет $REPO/prometheus/targets" >&2; exit 1; }

mkdir -p "$DATA/run" "$DATA/data/prometheus" "$REPO/prometheus/targets.local"
cfg="$DATA/run/prometheus.yml"
sed "s|__REPO__|$REPO|g" "$REPO/deploy/termux/prometheus.yml.tmpl" > "$cfg"

echo "config: $cfg"
"$DATA/bin/promtool" check config "$cfg" >/dev/null 2>&1 || true

exec "$DATA/bin/prometheus" \
  --config.file="$cfg" \
  --storage.tsdb.path="$DATA/data/prometheus" \
  --storage.tsdb.retention.time="$RETENTION" \
  --web.listen-address="$LISTEN" \
  --web.enable-lifecycle
