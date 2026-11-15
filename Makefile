export COMPOSE_FILE := $(CURDIR)/docker-compose.yml
export COMPOSE_ENV_FILES := $(CURDIR)/.env
# Общий мониторинг ботов: Prometheus + Grafana (host network, loopback).
.PHONY: help up down restart logs status targets reload verify

help: ## Справка
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

up: ## Поднять Prometheus + Grafana
	docker compose up -d

down: ## Остановить (данные в volume сохраняются)
	docker compose down

restart: ## Перезапустить
	docker compose restart

logs: ## Логи обоих сервисов
	docker compose logs -f

status: ## Статус контейнеров
	docker compose ps

targets: ## Проверить scrape-цели Prometheus (JSON)
	curl -fsS http://127.0.0.1:9091/api/v1/targets

reload: ## Перечитать конфиг Prometheus (обычно не нужно: file_sd сам подхватит)
	curl -fsS -X POST http://127.0.0.1:9091/-/reload

verify: ## Быстрая проверка сервисов
	@echo "Prometheus:"; curl -fsS -o /dev/null -w '  /-/ready %{http_code}\n' http://127.0.0.1:9091/-/ready || true
	@echo "Grafana:";    curl -fsS -o /dev/null -w '  /api/health %{http_code}\n' http://127.0.0.1:3000/api/health || true
