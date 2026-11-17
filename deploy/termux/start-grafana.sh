#!/data/data/com.termux/files/usr/bin/bash
# Grafana для Termux: слушает ТОЛЬКО 127.0.0.1:3000.
# Provisioning берётся из репозитория; путь к дашбордам подставляется на лету.
set -euo pipefail

REPO="${MON_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
DATA="${MON_DATA:-$HOME/.monitoring}"
DIST="$DATA/grafana-dist"

[ -x "$DIST/bin/grafana" ] || { echo "Нет $DIST/bin/grafana — сначала bash deploy/termux/install.sh" >&2; exit 1; }

if [ "${GRAFANA_ADMIN_PASSWORD:-}" = "" ]; then
  echo "ВНИМАНИЕ: GRAFANA_ADMIN_PASSWORD не задан, использую change-me" >&2
fi

mkdir -p "$DATA/run/grafana" "$DATA/data/grafana" "$DATA/logs/grafana" "$DATA/plugins"

# provisioning: копия из репозитория + правильный путь к дашбордам
rm -rf "$DATA/run/grafana/provisioning"
cp -r "$REPO/grafana/provisioning" "$DATA/run/grafana/provisioning"
sed -i "s|/var/lib/grafana/dashboards|$REPO/grafana/dashboards|g" \
  "$DATA/run/grafana/provisioning/dashboards/default.yml"

export GF_SERVER_HTTP_ADDR="${GRAFANA_ADDR:-127.0.0.1}"
export GF_SERVER_HTTP_PORT="${GRAFANA_PORT:-3000}"
export GF_PATHS_DATA="$DATA/data/grafana"
export GF_PATHS_LOGS="$DATA/logs/grafana"
export GF_PATHS_PLUGINS="$DATA/plugins"
export GF_PATHS_PROVISIONING="$DATA/run/grafana/provisioning"
export GF_SECURITY_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-change-me}"
export GF_USERS_ALLOW_SIGN_UP="false"
export GF_ANALYTICS_REPORTING_ENABLED="false"
export GF_ANALYTICS_CHECK_FOR_UPDATES="false"
export GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES="false"

exec "$DIST/bin/grafana" server --homepath "$DIST"
