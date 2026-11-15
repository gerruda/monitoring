# AGENTS.md — как подключить бота к общему мониторингу

Ты — агент, который разрабатывает **бота в другом проекте**. Этот репозиторий —
общий Prometheus + Grafana для всех ботов на VPS. Чтобы метрики твоего бота
появились в мониторинге, сделай ровно 4 шага. Ничего в код других ботов не
трогай.

## Шаг 1. Отдавай `/metrics` на отдельном loopback-listener

- Метрики — на **отдельном** HTTP-listener, а не на публичном порту бота.
- Конфиг-конвенция (env):

  ```dotenv
  METRICS_ENABLED=true
  METRICS_LISTEN=127.0.0.1:9092
  METRICS_PATH=/metrics
  ```

- Порт **уникален на VPS**. Уже заняты:

  | Порт | Что |
  |---|---|
  | 3000 | Grafana |
  | 9091 | Prometheus UI/API |
  | 9090 | health-check-in `/metrics` |
  | 8080 | volna HTTP (вебхуки + `/metrics`) |

  Новым ботам — **9092, 9093, …** (проверь `ss -ltn` перед выбором).
- Go-пример:

  ```go
  import (
      "net/http"
      "github.com/prometheus/client_golang/prometheus/promhttp"
  )

  mux := http.NewServeMux()
  mux.Handle("/metrics", promhttp.Handler()) // go_* и process_* уже внутри
  go http.ListenAndServe("127.0.0.1:9092", mux)
  ```

- **Не выставляй `/metrics` в интернет.** Если у бота один публичный HTTP-порт,
  закрой путь `/metrics` на nginx/фаерволе (только `127.0.0.1`).

## Шаг 2. Добавь файл таргета

Создай `prometheus/targets/<bot>.yml` в **этом** репозитории:

```yaml
- targets: ["127.0.0.1:9092"]
  labels:
    bot: my-bot
    project: my-project
    env: prod
```

- Файл подхватится автоматически (`file_sd`, обновление ≤30 с).
- **Не редактируй** `prometheus.yml` — для нового бота это не нужно.
- Имя файла = имя бота, чтобы не путаться.

Если бот в Docker и метрики не на host-сети, опубликуй порт только на loopback:

```yaml
ports:
  - "127.0.0.1:9092:9092"
```

## Шаг 3. Добавь отдельный дашборд бота

Правило: **один бот = один дашборд**. Не делай один общий дашборд с переменной
`bot` для всех ботов.

Создай `grafana/dashboards/<bot>.json` в **этом** репозитории:

- `uid`: `<bot>`, title: `<bot>`;
- **без** `templating` с `$bot` — дашборд уже про конкретного бота;
- в каждом запросе — фиксированный фильтр по лейблу:
  ```promql
  mybot_updates_total{bot="my-bot"}
  up{bot="my-bot"}
  process_resident_memory_bytes{bot="my-bot"}
  go_goroutines{bot="my-bot"}
  ```
- добавь панель здоровья target: `up{bot="my-bot"}`;
- Grafana подхватит файл автоматически (provisioning, ≤30 с).

Важно: `up`, `process_*`, `go_*` — общие метрики для всех ботов. **Без
`{bot="my-bot"}`** они смешают значения разных ботов. Это касается каждого
графика, а не только «памяти».

Дашборд **Bots — overview** (`bots-overview.json`) — только общий обзор фермы с
переменной `$bot`; его не нужно дублировать под каждого бота.

Пример для копирования — `grafana/dashboards/healthbot.json`; замени префикс
`healthbot_`/лейбл `health-check-in` на свои.

## Шаг 4. Проверь

```bash
# на VPS
curl -fsS 127.0.0.1:9092/metrics | head
curl -fsS http://127.0.0.1:9091/api/v1/targets | grep -o '"health":"[a-z]*"' | sort | uniq -c
```

- Prometheus UI (`http://127.0.0.1:9091/targets` после SSH-туннеля) — цель `UP`;
- `up{bot="my-bot"} == 1`;
- в Grafana появился дашборд `my-bot` (папка `bots`).

## Правила метрик

1. **Имя**: `<bot>_<subject>_<unit>`, например `mybot_requests_total`,
   `mybot_request_duration_seconds`. Не повторяй имена других ботов.
2. **Типы**: `_total` для счётчиков, `_seconds` для длительности, `_bytes` для
   размера.
3. **Лейблы низкой кардинальности**: `command`, `status`, `provider`, `model`,
   `kind`, `component`. Не более ~10 значений на лейбл.
4. **Никаких PII**: запрещены `user_id`, `chat_id`, `message`, `email`, `phone`,
   токены, тексты сообщений, произвольные строки от пользователя.
5. Подключай стандартные `go_*` / `process_*` (в Go — автоматически с
   `promhttp.Handler()`).
6. Не добавляй метрики «на всякий случай» — каждая метрика должна отвечать на
   вопрос эксплуатации.
7. **Дашборд — отдельный на каждого бота.** Общие метрики (`up`, `process_*`,
   `go_*`) обязательно фильтруй по `{bot="<bot>"}`.

Подробно: [`docs/metrics-contract.md`](docs/metrics-contract.md).

## Чего НЕ делать

- ❌ Не поднимай свой Prometheus/Grafana в проекте бота — только общий.
- ❌ Не редактируй `prometheus.yml` ради нового бота — используй `targets/`.
- ❌ Не публикуй `3000` (Grafana) и `9091` (Prometheus) наружу.
- ❌ Не добавляй лейблы с высокой кардинальностью (id, timestamp, путь).
- ❌ Не шли в метрики персональные данные (152-ФЗ).
- ❌ Не делай один общий дашборд с `$bot` вместо per-bot дашбордов.
- ❌ Не оставляй `process_*`/`go_*`/`up` без фильтра `{bot="<bot>"}`.

## Чек-лист PR

- [ ] `/metrics` на `127.0.0.1:<уникальный порт>`, отдельный listener.
- [ ] Стандартные `go_*`/`process_*` присутствуют.
- [ ] Добавлен `prometheus/targets/<bot>.yml` с лейблами `bot`, `project`, `env`.
- [ ] Добавлен `grafana/dashboards/<bot>.json` — отдельный дашборд без `$bot`.
- [ ] Все запросы дашборда фильтруют общие метрики по `{bot="<bot>"}`.
- [ ] Есть панель `up{bot="<bot>"}`.
- [ ] `curl 127.0.0.1:<PORT>/metrics` работает на VPS.
- [ ] Prometheus target `UP`, `up{bot="..."} == 1`.
- [ ] Нет PII и высококардинальных лейблов.
- [ ] В README бота указан порт метрик и как их включить.
