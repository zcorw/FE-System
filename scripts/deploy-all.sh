#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

QUESTION_BANK_DIR="${ROOT_DIR}/services/fe-question-bank-service"
TELEGRAM_BOT_DIR="${ROOT_DIR}/services/FE-telegram-bot"
DAILY_RUNNER_DIR="${ROOT_DIR}/services/FE-Daily-Runner"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required file is missing: ${path}" >&2
    exit 1
  fi
}

env_value() {
  local file="$1"
  local key="$2"
  local fallback="$3"
  local value
  value="$(awk -F= -v key="${key}" '
    $0 !~ /^[[:space:]]*#/ && $1 == key {
      sub(/^[^=]*=/, "")
      gsub(/^"|"$/, "")
      gsub(/^'\''|'\''$/, "")
      print
      exit
    }
  ' "${file}")"
  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
  else
    printf '%s' "${fallback}"
  fi
}

echo "==> Checking required environment files"
require_file "${QUESTION_BANK_DIR}/.env"
require_file "${TELEGRAM_BOT_DIR}/.env"
require_file "${DAILY_RUNNER_DIR}/.env"

echo "==> Ensuring shared Docker network"
docker network inspect fe-shared >/dev/null 2>&1 || docker network create fe-shared

echo "==> Deploying question-bank runtime"
cd "${QUESTION_BANK_DIR}"
docker compose --env-file .env up -d --build question-bank-runtime
QUESTION_BANK_RUNTIME_PORT="$(env_value .env QUESTION_BANK_RUNTIME_PORT 8000)"
curl -fsS "http://127.0.0.1:${QUESTION_BANK_RUNTIME_PORT}/health"
echo

echo "==> Deploying Telegram web, bot, and edge"
cd "${TELEGRAM_BOT_DIR}"
export WEB_IMAGE="${WEB_IMAGE:-fe-telegram-bot-web:local}"
export BOT_IMAGE="${BOT_IMAGE:-fe-telegram-bot-bot:local}"
export MIGRATE_IMAGE="${MIGRATE_IMAGE:-fe-telegram-bot-migrate:local}"
export HOST_CONFIG_DIR="${HOST_CONFIG_DIR:-${TELEGRAM_BOT_DIR}/config}"
export HOST_DATA_DIR="${HOST_DATA_DIR:-${TELEGRAM_BOT_DIR}/data}"
export HOST_ASSETS_DIR="${HOST_ASSETS_DIR:-${TELEGRAM_BOT_DIR}/docs/assets}"
export HOST_LOG_DIR="${HOST_LOG_DIR:-${TELEGRAM_BOT_DIR}/logs}"
export HOST_DEPLOY_DIR="${HOST_DEPLOY_DIR:-${TELEGRAM_BOT_DIR}/deploy}"
export HOST_ENV_FILE="${HOST_ENV_FILE:-${TELEGRAM_BOT_DIR}/.env}"
docker compose --env-file .env -f deploy/docker-compose.yml --profile tools run --rm migrate
docker compose --env-file .env -f deploy/docker-compose.yml up -d --build edge web bot
docker compose --env-file .env -f deploy/docker-compose.yml restart edge
docker compose --env-file .env -f deploy/docker-compose.yml ps
EDGE_PORT="$(env_value .env EDGE_PORT 3100)"
curl -fsS "http://127.0.0.1:${EDGE_PORT}/quiz/invalid-token" >/tmp/fe-quiz-smoke.html
wc -c /tmp/fe-quiz-smoke.html

echo "==> Building and validating Daily Runner"
cd "${DAILY_RUNNER_DIR}"
docker compose build fe-daily-runner
docker compose run --rm fe-daily-runner python scripts/daily_publish.py --validate-config
docker compose run --rm fe-daily-runner python scripts/daily_publish.py --health-check
docker compose run --rm fe-daily-runner python scripts/daily_publish.py --today --dry-run

echo "Deployment validation completed."
