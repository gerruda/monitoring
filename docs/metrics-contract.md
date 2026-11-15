# Контракт метрик для ботов

Общие правила, чтобы метрики разных ботов были совместимы с одним Prometheus и
одной Grafana.

## Endpoint

- HTTP `GET /metrics` в формате Prometheus text exposition.
- Listener: `127.0.0.1:<уникальный порт>` (loopback), отдельный от публичного
  HTTP бота.
- Конфиг-конвенция:

  ```dotenv
  METRICS_ENABLED=true
  METRICS_LISTEN=127.0.0.1:9092
  METRICS_PATH=/metrics
  ```

- `METRICS_ENABLED=false` по умолчанию, включать в проде.
- Валидация: `host:port` корректен; путь начинается с `/`; путь не конфликтует
  с `/healthz`.

## Именование

- Префикс — короткое имя бота: `mybot_`.
- Схема: `<bot>_<subject>_<unit>`.
- Счётчики: `_total` (`mybot_requests_total`).
- Длительности: `_seconds` (`mybot_request_duration_seconds`).
- Размеры: `_bytes`.
- Гистограммы: `_seconds` + бакеты (`.bucket`), суммы/количество — автоматически.
- Одна метрика = один смысл. Не смешивай «ошибки» и «латентность» в одном имени.

Примеры:

```text
mybot_updates_total{command="start",status="ok"}
mybot_update_duration_seconds{command="start"}
mybot_llm_requests_total{provider="ollama",model="qwen2.5:3b",status="ok"}
mybot_saves_total{kind="checkin",status="ok"}
go_goroutines
process_cpu_seconds_total
```

## Лейблы

**Можно** (низкая кардинальность):

- `command` — команда/сценарий;
- `status` — `ok` / `error` / `timeout`;
- `provider`, `model` — для LLM;
- `kind`, `component` — тип операции/подсистема;
- `env` — `prod` / `stage`.

**Нельзя** (PII и высокая кардинальность):

- `user_id`, `chat_id`, `message_id`, `username`, `email`, `phone`;
- текст сообщения, произвольный ввод пользователя;
- токены, ключи, сессии;
- timestamp, путь файла, request-id, IP как лейбл.

> Правило: если значение лейбла может принимать тысячи вариантов или содержит
> данные пользователя — это ошибка.

## Стандартные метрики

Go-боты через `promhttp.Handler()` автоматически отдают:

- `go_*` — горутины, GC, память;
- `process_*` — CPU, RSS, open fds.

Они уже используются в дашборде `Bots — overview` и в per-bot дашбордах
(там их обязательно фильтруют по `{bot="<bot>"}`).

## Дашборд

- **Один бот = один дашборд**: `grafana/dashboards/<bot>.json` (uid и title —
  имя бота). Grafana подхватит файл автоматически (≤30 с).
- Без переменной `$bot`: дашборд уже про конкретного бота.
- В каждом запросе — фиксированный фильтр:
  ```promql
  mybot_updates_total{bot="my-bot"}
  up{bot="my-bot"}
  process_resident_memory_bytes{bot="my-bot"}
  go_goroutines{bot="my-bot"}
  ```
- Обязательна панель здоровья target: `up{bot="my-bot"}`.
- Общие метрики (`up`, `process_*`, `go_*`) **всегда** фильтруй по
  `{bot="<bot>"}` — иначе на графике смешаются все боты.
- `bots-overview.json` — только общий обзор фермы с переменной `$bot`; он не
  заменяет per-bot дашборды.

## Пример на Go

```go
package metrics

import (
    "net/http"

    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var updates = prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "mybot_updates_total",
        Help: "Обработанные апдейты по командам и статусу.",
    },
    []string{"command", "status"},
)

func init() { prometheus.MustRegister(updates) }

// StartListener поднимает отдельный loopback-listener для /metrics.
func StartListener(addr, path string) error {
    mux := http.NewServeMux()
    mux.Handle(path, promhttp.Handler())
    go func() { _ = http.ListenAndServe(addr, mux) }()
    return nil
}
```

## Проверка

```bash
# формат и наличие своих метрик
curl -fsS 127.0.0.1:9092/metrics | grep mybot_

# стандартные метрики
curl -fsS 127.0.0.1:9092/metrics | grep -E '^(go_|process_)' | head

# Prometheus видит цель
curl -fsS http://127.0.0.1:9091/api/v1/targets | python3 -m json.tool | grep -A2 mybot
```

## Безопасность

- Listener только на `127.0.0.1`.
- Если бот публикует HTTP-порт: `location /metrics { deny all; }` в nginx или
  фаервол «только 127.0.0.1».
- В метриках нет персональных данных (152-ФЗ).
- Prometheus/Grafana наружу не публикуются (SSH-туннель).

## Память и кардинальность

- Каждая новая серия = память Prometheus. Держи число серий < нескольких тысяч
  на бота.
- Не добавляй лейблы «на будущее».
- Гистограммы — с разумным набором бакетов (`prometheus.DefBuckets` или свои).
