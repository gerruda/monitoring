# Мониторинг на телефоне (Termux, без Docker)

Нативная (без Docker) замена `docker-compose.yml` из корня репозитория для
Redmi Note 7 / Termux. Те же конфиги и дашборды, те же принципы:

- Prometheus слушает **только `127.0.0.1:9091`**, Grafana — **только `127.0.0.1:3000`**;
- наружу ничего не публикуется, доступ — через SSH-туннель на порт 8022;
- таргеты ботов — те же файлы `prometheus/targets/*.yml`, `file_sd` подхватывает
  изменения без перезапуска;
- дашборды берутся из `grafana/dashboards/` через provisioning.

Отличие от VPS-варианта только в путях: конфиги генерируются из шаблона, данные
и бинарники лежат вне git-репозитория (`~/.monitoring`).

## Что куда кладётся

| Путь | Что |
|---|---|
| `~/monitoring` | git-репозиторий (этот каталог), `MON_REPO` |
| `~/.monitoring/bin` | `prometheus`, `promtool`, `grafana` |
| `~/.monitoring/data/prometheus` | TSDB Prometheus (retention 14d) |
| `~/.monitoring/data/grafana` | БД Grafana |
| `~/.monitoring/run` | сгенерированные конфиги |
| `~/.monitoring/logs` | логи |

## Установка

На телефоне в Termux (репозиторий удобно скопировать с ПК по scp — см. ниже):

```bash
pkg install -y git curl tar
# вариант 1: git clone
cd ~ && git clone <URL> monitoring
# вариант 2: с ПК
#   scp -P 8022 -r ./monitoring u0_a123@<IP-телефона>:~/

cd ~/monitoring
bash deploy/termux/install.sh          # Prometheus 2.55.1 + Grafana 11.1.0 (arm64)
bash deploy/termux/start-prometheus.sh &
GRAFANA_ADMIN_PASSWORD='свой-пароль' bash deploy/termux/start-grafana.sh &
```

Версии по умолчанию совпадают с `docker-compose.yml` (Prometheus 2.55.1,
Grafana 11.1.0, загрузка ~105 + ~119 МБ). Другие версии:

```bash
PROM_VER=3.16.0 GRAFANA_VER=12.2.0 bash deploy/termux/install.sh
```

Проверка на телефоне:

```bash
curl -fsS http://127.0.0.1:9091/-/ready     # Ready
curl -fsS http://127.0.0.1:3000/api/health  # {"database":"ok",...}
curl -fsS http://127.0.0.1:9091/api/v1/targets | head -c 400
```

## Доступ с ноутбука (Windows/Linux)

Grafana и Prometheus наружу не смотрят, поэтому только через туннель:

```powershell
ssh -N -p 8022 -L 3000:127.0.0.1:3000 -L 9091:127.0.0.1:9091 u0_a123@192.168.x.x
```

- Grafana: <http://127.0.0.1:3000> (admin / пароль из `GRAFANA_ADMIN_PASSWORD`,
  по умолчанию `change-me` — поменяй до первого запуска или через UI);
- Prometheus: <http://127.0.0.1:9091> (`/targets`, `/graph`).

## Где живут боты — два сценария

### A. Боты на телефоне (всё локально)

Ничего менять не нужно: боты слушают `METRICS_LISTEN=127.0.0.1:<порт>`,
таргеты — `127.0.0.1:<порт>` из `prometheus/targets/*.yml`. Метрики физически
не покидают телефон.

### B. Боты остались на VPS (телефон только мониторит)

**Не открывай `/metrics` в интернет.** На телефоне подними локальный форвард
до VPS и скрапь через `127.0.0.1`:

```bash
# в Termux, в фоне (лучше через termux-services или boot-скрипт)
nohup ssh -N -p 22 -o ServerAliveInterval=30 -L 19090:127.0.0.1:9090 user@VPS \
  >> ~/.monitoring/logs/tunnel-health.log 2>&1 &
```

Таргет в `prometheus/targets/health-check-in.yml`:

```yaml
- targets: ["127.0.0.1:19090"]
  labels:
    bot: health-check-in
    project: health
    env: prod
```

Трафик идёт по SSH (шифрован), на VPS порт `9090` остаётся на loopback.
Так же добавляются остальные боты: по одному `-L` на порт.

Если бот временно не запущен, убери его таргет, иначе цель будет вечно `DOWN`:
`mv prometheus/targets/<bot>.yml prometheus/targets/<bot>.yml.disabled`
(`file_sd` читает только `*.yml`; верни обратно, когда бот поднимется).
Новый порт в `TUNNEL_PORTS` добавляй через `stop-tunnels.sh` → правка env →
`start-tunnels.sh`.

Альтернатива без туннелей — **Tailscale** на телефоне и VPS, боты слушают
`METRICS_LISTEN=<tailscale-IP>:<порт>`, таргеты — этот IP. Сеть приватная,
но не loopback — значит метрики видны всем устройствам tailnet.

### C. Бот на другом хосте в LAN (например, `10.0.1.66:8080`)

Телефон и бот в одной сети — туннель не нужен, скрапим по LAN-адресу. Такие
адреса кладём в `prometheus/targets.local/` (каталог в `.gitignore`, чтобы не
тащить домашние IP в общий репозиторий):

```bash
mkdir -p prometheus/targets.local
cat > prometheus/targets.local/volna.yml <<'EOF'
- targets: ["10.0.1.66:8080"]
  labels:
    bot: volna
    project: volna
    env: prod
EOF
```

Сначала проверь с телефона, что метрики вообще видны:
`curl -fsS http://10.0.1.66:8080/metrics | head`.

Если `connection refused` — бот слушает только loopback того хоста. Тогда либо
`METRICS_LISTEN=10.0.1.66:8080` (и фаервол только на LAN), либо SSH-форвард с
телефона до этого хоста (`-L 18080:127.0.0.1:8080`), а в таргете — `127.0.0.1:18080`.

**Если бот в виртуалке с NAT** (VirtualBox, адрес вида `10.0.2.15`), из LAN его не
видно. Варианты:
1. Проброс порта VirtualBox: `Host 10.0.1.66:18080 → Guest 8080` (плюс правило
   Windows Firewall на 18080, профиль Private) — таргет `10.0.1.66:18080`.
2. Переключить адаптер VM в **Bridged** — виртуалка получит `10.0.1.x`, таргет
   прямо на её IP.
3. Reverse-SSH из VM на телефон: в VM
   `ssh -p 8022 -fN -R 18080:127.0.0.1:8080 u0_aXXX@10.0.1.123`,
   таргет `127.0.0.1:18080` (ничего в LAN не открывается).
Учти: если `8080` у бота смотрит в интернет, `/metrics` надо закрыть на
nginx/фаерволе — это отдельный контур, Prometheus тут не при чём.

Продвинутый вариант: Prometheus на VPS в режиме agent + `remote_write` на
телефон (`--web.enable-remote-write-receiver`), если хочется хранить историю
на телефоне, а скрапить с VPS.

## Туннели к VPS (боты остаются на VPS)

Если боты живут на VPS, а Prometheus — на телефоне: наружу на VPS ничего не
публикуем, а форвардим loopback-порты через SSH **с телефона**.

```bash
# один раз: ключ и доступ
pkg install -y openssh
ssh-keygen -t ed25519 -C termux-monitoring
ssh-copy-id -p 22 user@VPS

# конфиг туннелей
cp deploy/termux/tunnels.env.example ~/.monitoring/tunnels.env
nano ~/.monitoring/tunnels.env        # VPS_HOST, TUNNEL_PORTS

bash deploy/termux/start-tunnels.sh
curl -fsS http://127.0.0.1:9090/metrics | head    # health-check-in через туннель
```

По умолчанию порт на телефоне совпадает с портом на VPS, поэтому
`prometheus/targets/*.yml` менять не нужно. Если локальный порт занят
(например, `8080` ушёл под `llama-server`) — задай пару `local:remote` в
`TUNNEL_PORTS` и поправь таргет бота.

Остановить: `bash deploy/termux/stop-tunnels.sh`. Автозапуск — `boot.sh`
поднимает туннели, если файл `~/.monitoring/tunnels.env` существует.

## Автозапуск после перезагрузки

Готовый скрипт — `deploy/termux/boot.sh` (нужен Termux:Boot + автозапуск
Termux в MIUI):

```bash
# пароль Grafana для автозапуска (файл вне git)
echo "GRAFANA_ADMIN_PASSWORD=свой-пароль" > ~/.monitoring/env
chmod 600 ~/.monitoring/env

mkdir -p ~/.termux/boot
cp deploy/termux/boot.sh ~/.termux/boot/monitoring.sh
chmod +x ~/.termux/boot/monitoring.sh
```

Что поднимается после перезагрузки: туннели (если есть `tunnels.env`) →
Prometheus → Grafana. Данные Prometheus/Grafana лежат в `~/.monitoring/data`,
поэтому история и пароль администратора переживают перезагрузку.
Termux:Boot выполняет скрипт только если Termux хотя бы раз запускали после
установки Termux:Boot и в MIUI включён автозапуск + «Без ограничений».

Либо `termux-services` — оберни `start-*.sh` в `$PREFIX/var/service/<name>/run`
(тогда не нужен `nohup`, runit сам держит процесс).

## Память (4 ГБ, Android)

| Компонент | ОЗУ |
|---|---|
| Prometheus (14d, 2–5 целей) | ~150–220 МБ |
| Grafana | ~250–400 МБ |
| llama-server 1.5B Q4 | ~1,3–1,7 ГБ |

**Grafana и LLM одновременно не запускать** — вместе не влезают. Варианты:
держать LLM по требованию; поднять Grafana на ноутбуке (datasource
`http://127.0.0.1:9091` через тот же SSH-туннель); снизить retention до `7d`.

## Диагностика

| Симптом | Проверь |
|---|---|
| `start-prometheus.sh` падает | `bash -x deploy/termux/start-prometheus.sh`, права на `~/.monitoring` |
| target `DOWN` | `curl -s 127.0.0.1:<PORT>/metrics` в Termux; `ss -ltn` (пакет `iproute2`) |
| Grafana «No data» | datasource `http://127.0.0.1:9091`, в Prometheus есть `up` |
| Grafana не открывается с ноутбука | туннель `-L 3000:127.0.0.1:3000`, порт 8022 открыт локально |
| OOM/Android убил процессы | `termux-wake-lock`, «Без ограничений» в батарее, retention `7d` |

## Отличия от Docker-варианта

- нет `network_mode: host` — не нужен, всё и так на loopback;
- нет `mem_limit` — лимиты ОЗУ даёт Android, поэтому важнее retention и
  «не запускать лишнее»;
- бинарники статические (`linux-arm64`), поэтому запускаются прямо в Termux
  без proot: Prometheus и Grafana — Go-приложения без cgo.
