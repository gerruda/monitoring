# Переезд на общий мониторинг

Сейчас `health-check-in` держит свой Prometheus+Grafana в
`PDF/health/бот/health-check-in/deploy/docker-compose.monitoring.yml`.
Этот репозиторий (`bots/monitoring`) заменяет его: один стек на все боты.

Порты не меняются: метрики health-check-in — `127.0.0.1:9090`, Prometheus UI/API
— `127.0.0.1:9091`, Grafana — `127.0.0.1:3000`. SSH-туннель для Grafana
(`-L 3000:127.0.0.1:3000`) остаётся тем же.

## Что понадобится

- VPS с Docker.
- Запущенный `health-check-in` с `METRICS_ENABLED=true` и
  `METRICS_LISTEN=127.0.0.1:9090`.
- Доступ на VPS и локальный SSH-туннель к Grafana.

## Шаги

### 1. Скопировать репозиторий на VPS

```bash
rsync -a --exclude .git . user@VPS:/opt/monitoring/   # из каталога репозитория
# или git clone, если репозиторий в git
```

### 2. Настроить

```bash
ssh vps
cd /opt/monitoring
cp .env.example .env
# задать GRAFANA_ADMIN_PASSWORD (не оставляй change-me)
```

### 3. Убедиться, что бот отдаёт метрики

```bash
curl -fsS 127.0.0.1:9090/metrics | grep healthbot_ | head
```

Если пусто — проверь `.env` бота: `METRICS_ENABLED=true`,
`METRICS_LISTEN=127.0.0.1:9090`, и что бот перезапущен.

### 4. Остановить старый мониторинг

```bash
cd /opt/healthbot/monitoring   # или где лежит docker-compose.monitoring.yml
docker compose -f docker-compose.monitoring.yml down
```

Данные в volume (`healthbot_prometheus-data`, `healthbot_grafana-data`)
остаются; контейнеры останавливаются. Историю TSDB автоматически перенести
нельзя — если она важна, сначала заархивируй volume.

### 5. Запустить общий мониторинг

```bash
cd /opt/monitoring
make up
make verify
make targets
```

Ожидаемо: `/targets` содержит `bot="health-check-in"` со статусом `UP`.

### 6. Проверить Grafana

Туннель (как раньше):

```bash
ssh -N -L 3000:127.0.0.1:3000 -L 9091:127.0.0.1:9091 user@VPS
```

- Grafana: http://127.0.0.1:3000 (admin / пароль из `.env`)
- Prometheus: http://127.0.0.1:9091/targets

Ожидаемо:
- datasource **Prometheus** (`http://127.0.0.1:9091`) провижнится сам;
- дашборды **Bots — overview** и **healthbot** доступны;
- `up{job="bots"} == 1`.

### 7. Добавить остальных ботов

Для каждого бота — файл `prometheus/targets/<bot>.yml` (см.
[`AGENTS.md`](../AGENTS.md)). Пример уже есть: `volna.yml`
(`127.0.0.1:8080`).

### 8. Убрать старое (опционально)

После проверки можно:
- удалить из `health-check-in` файлы `deploy/docker-compose.monitoring.yml`,
  `deploy/prometheus.yml`, `deploy/grafana*` (или пометить deprecated);
- обновить `docs/operations/deploy-vps.md`: мониторинг теперь в
  `/opt/monitoring`;
- удалить старые volume, если история не нужна:

  ```bash
  docker volume rm healthbot_prometheus-data healthbot_grafana-data
  ```

## Откат

```bash
cd /opt/monitoring && make down
cd /opt/healthbot/monitoring && docker compose -f docker-compose.monitoring.yml up -d
```

Порты те же, конфликтов не будет.

## Важно

- **Не запускай два Prometheus одновременно** — оба займут `127.0.0.1:9091`.
- `network_mode: host` обязателен: Prometheus скрапит loopback-адреса ботов.
- Если бот в Docker без host-network, опубликуй порт метрик только на loopback:
  `ports: ["127.0.0.1:9092:9092"]`.
- `volna` отдаёт `/metrics` на `8080` вместе с вебхуками. Если `8080` публичный,
  закрой `/metrics` снаружи (nginx/фаервол) — Prometheus ходит с `127.0.0.1`.
