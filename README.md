# Мониторинг ботов (общие Prometheus + Grafana)

Один общий Prometheus и одна Grafana для **всех ботов на VPS**. Боты только
отдают `/metrics`; Prometheus сам их опрашивает. Ничего общего в код ботов не
тянется.

```
бот A  ── 127.0.0.1:9090/metrics ─┐
бот B  ── 127.0.0.1:8080/metrics ─┤   Prometheus (127.0.0.1:9091)  ──  Grafana (127.0.0.1:3000)
бот C  ── 127.0.0.1:9092/metrics ─┘        ▲ file_sd: targets/*.yml
```

Prometheus и Grafana работают в `network_mode: host` и слушают **только
127.0.0.1**. Снаружи — доступ через SSH-туннель.

## Порты на VPS

| Порт | Что | Доступ |
|---|---|---|
| `3000` | Grafana | `127.0.0.1` + SSH-туннель |
| `9091` | Prometheus UI/API | `127.0.0.1` + SSH-туннель |
| `9090` | метрики `health-check-in` | `127.0.0.1` (бот) |
| `8080` | `volna`: HTTP (вебхуки + `/metrics`) | см. «Безопасность» |
| `9092+` | метрики новых ботов | `127.0.0.1` (бот) |

> 9090 часто занят метриками бота, поэтому UI Prometheus — на **9091**.

## Быстрый старт

```bash
cd /home/flash/work/bots/monitoring        # на VPS: /opt/monitoring
cp .env.example .env                       # задай GRAFANA_ADMIN_PASSWORD
make up                                    # docker compose up -d
make verify                                # /-/ready и /api/health
make targets                               # scrape-цели (JSON)
```

## Доступ через SSH-туннель

С локальной машины:

```bash
ssh -N -L 3000:127.0.0.1:3000 -L 9091:127.0.0.1:9091 user@VPS
```

- Grafana: http://127.0.0.1:3000 (логин `admin`, пароль из `.env`)
- Prometheus: http://127.0.0.1:9091 (Targets: `/targets`)

Альтернатива — `ssh -L 3000:127.0.0.1:3000 user@VPS` только для Grafana (как
было в health-check-in).

## Как добавить нового бота (для агента)

1. **Бот отдаёт `/metrics`** на отдельном listener, например
   `127.0.0.1:9092` (порт — уникальный, только loopback).
   Конфиг-конвенция: `METRICS_ENABLED=true`, `METRICS_LISTEN=127.0.0.1:9092`,
   `METRICS_PATH=/metrics`.
2. **Добавь файл таргета** `prometheus/targets/<bot>.yml`:

   ```yaml
   - targets: ["127.0.0.1:9092"]
     labels:
       bot: my-bot
       project: my-project
       env: prod
   ```

3. **Добавь отдельный дашборд** `grafana/dashboards/<bot>.json` (uid/title — имя
   бота, **без** переменной `$bot`; в каждом запросе — фильтр `{bot="my-bot"}`).
   Общий **Bots — overview** — только обзор фермы, он не заменяет дашборд бота.
4. **Подожди ≤30 секунд** — `file_sd` и provisioning сами подхватят изменения,
   перезапуск Prometheus/Grafana не нужен.
5. **Проверь**:
   - `curl -s 127.0.0.1:9092/metrics | head` — на VPS;
   - `make targets` или Prometheus → `/targets` — цель `UP`;
   - Grafana → дашборд `my-bot` (папка `bots`), `up{bot="my-bot"} == 1`.

Подробные правила — [`AGENTS.md`](AGENTS.md) и
[`docs/metrics-contract.md`](docs/metrics-contract.md).

## Контракт метрик (кратко)

- Имена: префикс `<bot>_`, например `mybot_requests_total`.
- Лейблы — низкой кардинальности (`command`, `status`, `provider`, `kind`).
- **Никаких PII**: ни `user_id`, ни `chat_id`, ни текста сообщений, ни токенов.
- Подключай стандартные `go_*`/`process_*` (Go) — они уже есть в дашборде.
- `/metrics` не должен быть доступен из интернета.
- **Один бот = один дашборд**; общие `up`/`process_*`/`go_*` фильтруй по
  `{bot="<bot>"}`, иначе значения разных ботов смешаются.

## Безопасность

- Prometheus и Grafana слушают `127.0.0.1` — наружу не публикуй.
- Фаервол: порты `3000`, `9091` наружу закрыты; SSH — только по ключу.
- Grafana: задай пароль в `.env`, sign-up выключен.
- Если бот публикует HTTP-порт (например, `volna` на `8080`), закрой
  `/metrics` от внешних: nginx `location /metrics { deny all; }` или фаервол
  «только 127.0.0.1 / IP Prometheus».
- Метрики не должны содержать персональных данных (152-ФЗ).

## Память (VPS 1 ГБ)

В compose заданы лимиты `220m` на Prometheus и `220m` на Grafana, retention
14 дней. На 1 ГБ с несколькими ботами может быть тесно: при OOM
увеличь VPS/добавь swap, снизь retention
(`--storage.tsdb.retention.time=7d`) или лимиты.

## Обновление конфигурации

- **Добавить/удалить бота** — только файл в `prometheus/targets/`. Автоподхват.
- **Изменить `prometheus.yml`** — `make reload` (включён `--web.enable-lifecycle`).
- **Дашборды** — положи JSON в `grafana/dashboards/`, Grafana подхватит через
  провижнинг (≤30 с).
- **Пароль Grafana** — поменяй `.env` и `make restart` (или через UI).

## Траблшутинг

| Симптом | Проверь |
|---|---|
| цель `DOWN` | на VPS: `curl -s 127.0.0.1:<PORT>/metrics`; порт слушается (`ss -ltn`); не 0.0.0.0-за фаерволом |
| `file_sd` не видит файл | файл должен лежать в `prometheus/targets/` и оканчиваться `.yml`; YAML валиден; `docker compose logs prometheus` |
| Grafana «No data» | datasource `http://127.0.0.1:9091`; в Prometheus `up` есть |
| Порт занят | `ss -ltn`; поменяй порт в compose/provisioning/targets |
| Grafana не открывается | туннель `-L 3000:127.0.0.1:3000`; контейнер запущен (`make status`) |
| OOM | `docker stats`; снизь retention/лимиты |

## Переезд с мониторинга внутри проекта

См. [`docs/MIGRATION.md`](docs/MIGRATION.md) — как перевести
`health-check-in` (и другие проекты) на этот общий стек.

## Структура

```
monitoring/
├── docker-compose.yml          # prometheus + grafana (host network)
├── .env.example                # GRAFANA_ADMIN_PASSWORD
├── Makefile                    # up/down/logs/status/targets/reload/verify
├── prometheus/
│   ├── prometheus.yml          # file_sd + self-scrape
│   └── targets/                # ← сюда агенты добавляют <bot>.yml
├── grafana/
│   ├── provisioning/           # datasource + dashboards provider
│   └── dashboards/             # bots-overview.json, healthbot.json, <bot>.json...
├── AGENTS.md                   # правила подключения ботов (для агентов)
└── docs/
    ├── MIGRATION.md
    └── metrics-contract.md
```
