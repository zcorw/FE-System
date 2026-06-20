# FE Production Deployment Guide

This document describes how to deploy the complete FE system on a production
VPS. It covers the three projects under this directory:

- `fe-question-bank-service`: FastAPI Runtime for FE question data and assets.
- `FE-telegram-bot`: Telegram quiz web app, webhook bot, and Docker edge proxy.
- `FE-Daily-Runner`: Daily study page generator, static publisher, and Telegram notifier.

Do not commit real `.env` files, API keys, bot tokens, private keys, generated
runtime state, logs, or SQLite WAL/SHM files.

## 1. Production Topology

Recommended layout:

```text
Internet
  |
  v
VPS Nginx + Certbot
  |-- /daily/                 -> static files under /var/www/<site>-daily/
  |-- /telegram/webhook/      -> http://127.0.0.1:3100
  |-- /quiz/, /api/, /assets/ -> http://127.0.0.1:3100

Docker network: fe-shared
  |-- question-bank-runtime   -> http://question-bank-runtime:8000
  |-- FE-telegram-bot web
  |-- FE-telegram-bot bot
  |-- FE-telegram-bot edge    -> publishes 127.0.0.1:3100
  |-- FE-Daily-Runner one-shot containers
```

The host Nginx `upstream` name, for example `fe_quiz_edge`, is only a local
Nginx alias. It can point to `127.0.0.1:3100`; it is not a Docker container
hostname.

## 2. Host Prerequisites

Install these on the VPS:

```bash
sudo apt-get update
sudo apt-get install -y git curl nginx certbot python3-certbot-nginx
```

Install Docker Engine and Docker Compose Plugin using the official Docker
instructions for the target OS, then verify:

```bash
docker --version
docker compose version
```

Create the shared Docker network once:

```bash
docker network inspect fe-shared >/dev/null 2>&1 || docker network create fe-shared
```

Recommended production directories:

```bash
sudo mkdir -p /opt/fe-question-bank/data
sudo mkdir -p /opt/fe-question-bank/public/assets/fe-siken
sudo mkdir -p /opt/fe-quiz-bot/config
sudo mkdir -p /opt/fe-quiz-bot/data
sudo mkdir -p /opt/fe-quiz-bot/logs
sudo mkdir -p /var/www/example-daily
sudo chown -R "$USER:$USER" /opt/fe-question-bank /opt/fe-quiz-bot /var/www/example-daily
```

Clone or copy this root workspace to the production host, for example:

```bash
cd /home/dev
git clone <repo-url-for-root-or-copy-projects> FE
cd /home/dev/FE
```

If the three projects are separate Git repositories, clone each project under
the same root names used in this document.

## 3. Secrets And Environment Files

Create real `.env` files directly on the VPS. Never commit them.

### 3.1 `fe-question-bank-service/.env`

Start from:

```bash
cd /home/dev/FE/services/fe-question-bank-service
cp .env.vps.example .env
```

Production values:

```env
QUESTION_BANK_RUNTIME_HOST=127.0.0.1
QUESTION_BANK_RUNTIME_PORT=8000
QUESTION_BANK_ADMIN_HOST=127.0.0.1
QUESTION_BANK_ADMIN_PORT=8001
QUESTION_ASSET_ROOT=/app/public/assets/fe-siken
HOST_DATA_DIR=/opt/fe-question-bank/data
HOST_ASSET_DIR=/opt/fe-question-bank/public/assets/fe-siken
ADMIN_API_TOKEN=<long-random-admin-token>
LOG_LEVEL=info
```

Required runtime data under `HOST_DATA_DIR`:

```text
fe_siken_questions.sqlite
question_keyword_taxonomy.json
question_topic_mappings.json
```

Required image asset root:

```text
/opt/fe-question-bank/public/assets/fe-siken/
```

Back up the SQLite database, keyword JSON files, and image assets together.

### 3.2 `FE-telegram-bot/.env`

Start from:

```bash
cd /home/dev/FE/services/FE-telegram-bot
cp .env.production.example .env
```

Production values:

```env
PUBLIC_BASE_URL=https://example.com
OPENAI_API_KEY=<openai-api-key>
TELEGRAM_BOT_TOKEN=<telegram-bot-token>
TELEGRAM_WEBHOOK_PATH_SECRET=<long-random-path-secret>
TELEGRAM_WEBHOOK_SECRET_TOKEN=<long-random-header-secret>
TELEGRAM_WEBHOOK_HEADER_SECRET=<same-as-telegram-webhook-secret-token>
TELEGRAM_AUTO_SET_WEBHOOK=true
EDGE_HOST=127.0.0.1
EDGE_PORT=3100
QUESTION_BANK_MODE=sqlite
QUESTION_BANK_SERVICE_URL=http://question-bank-runtime:8000
```

Required local files:

```text
FE-telegram-bot/config/app.yaml
FE-telegram-bot/data/app.sqlite
FE-telegram-bot/data/fe_siken_questions.sqlite
```

`app.sqlite` is application state. Include it in production backups.

### 3.3 `FE-Daily-Runner/.env`

Start from:

```bash
cd /home/dev/FE/services/FE-Daily-Runner
cp .env.example .env
```

Production values:

```env
TZ=Asia/Tokyo
QUESTION_BANK_SERVICE_URL=http://question-bank-runtime:8000
QUESTION_BANK_TIMEOUT_SECONDS=20
QUESTION_BANK_RETRY_COUNT=2

OPENAI_API_KEY=<openai-api-key>
OPENAI_MODEL=gpt-5.5
OPENAI_REASONING_EFFORT=low
OPENAI_TEXT_VERBOSITY=medium

OUTPUT_DIR=site
STATIC_PUBLISH_DIR=/app/published-site
TEMPLATE_DIR=templates
MARKDOWN_COMPAT_ENABLED=false
MARKDOWN_OUTPUT_DIR=docs
ASSET_PROXY_BASE_PATH=/assets/fe-siken
PAGE_BASE_URL=https://example.com/daily
EXISTING_PAGE_POLICY=fail

STUDY_PLAN_PATH=references/legacy-project/june-study-plan.md
WEAK_POINTS_PATH=references/personal-context/weak_points.md
MISTAKE_LOG_PATH=references/personal-context/mistake_log.md
PROGRESS_CONTEXT_PATH=references/personal-context/progress.md

TELEGRAM_BOT_TOKEN=<telegram-bot-token>
TELEGRAM_CHAT_ID=<telegram-chat-id>
```

Required input documents:

```text
FE-Daily-Runner/references/legacy-project/june-study-plan.md
FE-Daily-Runner/references/personal-context/weak_points.md
FE-Daily-Runner/references/personal-context/mistake_log.md
FE-Daily-Runner/references/personal-context/progress.md
```

## 4. Deploy Order

### 4.1 Start Question Bank Runtime

```bash
cd /home/dev/FE/services/fe-question-bank-service
docker compose --env-file .env up -d --build question-bank-runtime
curl -fsS http://127.0.0.1:8000/health
```

Expected result:

```json
{"ok":true,"database":"ready","readOnly":true}
```

Only start Admin API during a maintenance window:

```bash
docker compose --env-file .env --profile admin up -d --build question-bank-admin
```

Stop Admin API after maintenance:

```bash
docker compose --env-file .env --profile admin stop question-bank-admin
```

### 4.2 Start Telegram Web, Bot, And Edge

```bash
cd /home/dev/FE/services/FE-telegram-bot

export WEB_IMAGE=fe-telegram-bot-web:local
export BOT_IMAGE=fe-telegram-bot-bot:local
export MIGRATE_IMAGE=fe-telegram-bot-migrate:local
export HOST_CONFIG_DIR=/home/dev/FE/services/FE-telegram-bot/config
export HOST_DATA_DIR=/home/dev/FE/services/FE-telegram-bot/data
export HOST_ASSETS_DIR=/home/dev/FE/services/FE-telegram-bot/docs/assets
export HOST_LOG_DIR=/home/dev/FE/services/FE-telegram-bot/logs
export HOST_DEPLOY_DIR=/home/dev/FE/services/FE-telegram-bot/deploy
export HOST_ENV_FILE=/home/dev/FE/services/FE-telegram-bot/.env

docker compose --env-file .env -f deploy/docker-compose.yml --profile tools run --rm migrate
docker compose --env-file .env -f deploy/docker-compose.yml up -d --build edge web bot
docker compose --env-file .env -f deploy/docker-compose.yml ps
curl -fsS http://127.0.0.1:3100/quiz/invalid-token >/tmp/fe-quiz-smoke.html
wc -c /tmp/fe-quiz-smoke.html
```

If `web` or `bot` is recreated and `edge` returns `502`, restart `edge` so Nginx
resolves the new container IP:

```bash
docker compose --env-file .env -f deploy/docker-compose.yml restart edge
```

### 4.3 Validate Daily Runner

```bash
cd /home/dev/FE/services/FE-Daily-Runner
docker compose build fe-daily-runner
docker compose run --rm fe-daily-runner python scripts/daily_publish.py --validate-config
docker compose run --rm fe-daily-runner python scripts/daily_publish.py --health-check
docker compose run --rm fe-daily-runner python scripts/daily_publish.py --today --dry-run
```

Expected health-check output includes:

```text
question bank runtime is healthy
```

To publish a real page and send Telegram:

```bash
docker compose run --rm -e EXISTING_PAGE_POLICY=overwrite fe-daily-runner \
  python scripts/daily_publish.py --today --notify
```

## 5. VPS Nginx

Create an Nginx site file on the VPS. Replace `example.com` and daily static
root paths before use:

```nginx
upstream fe_quiz_edge {
  server 127.0.0.1:3100;
  keepalive 32;
}

server {
  listen 80;
  listen [::]:80;
  server_name example.com;

  location /.well-known/acme-challenge/ {
    root /var/www/html;
  }

  location / {
    return 301 https://$host$request_uri;
  }
}

server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name example.com;

  ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
  ssl_session_timeout 1d;
  ssl_session_cache shared:FETLS:10m;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers off;

  client_max_body_size 2m;

  add_header X-Content-Type-Options nosniff always;
  add_header Referrer-Policy strict-origin-when-cross-origin always;

  location = /daily {
    return 301 /daily/;
  }

  location /daily/ {
    alias /var/www/example-daily/;
    index index.html;
    try_files $uri $uri/ =404;
  }

  location /telegram/webhook/ {
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_pass http://fe_quiz_edge;
  }

  location / {
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_pass http://fe_quiz_edge;
  }
}
```

Install and enable:

```bash
sudoedit /etc/nginx/sites-available/example.com
sudo ln -s /etc/nginx/sites-available/example.com /etc/nginx/sites-enabled/example.com
sudo nginx -t
sudo systemctl reload nginx
```

For a new domain, obtain certificates:

```bash
sudo certbot --nginx -d example.com
```

Check:

```bash
curl -fsS https://example.com/quiz/invalid-token >/tmp/fe-quiz-smoke.html
curl -fsS https://example.com/daily/ >/tmp/fe-daily-index.html
```

## 6. Daily Schedule With systemd Timer

This production setup uses a host-level `systemd` timer to run a one-shot Docker
Compose command. It does not require cron inside the container.

Install the provided units:

```bash
sudo cp /home/dev/FE/deploy/systemd/fe-daily-runner.service /etc/systemd/system/fe-daily-runner.service
sudo cp /home/dev/FE/deploy/systemd/fe-daily-runner.timer /etc/systemd/system/fe-daily-runner.timer
sudo systemctl daemon-reload
sudo systemctl enable --now fe-daily-runner.timer
```

Inspect schedule and status:

```bash
systemctl list-timers fe-daily-runner.timer
systemctl status fe-daily-runner.timer
```

Run manually:

```bash
sudo systemctl start fe-daily-runner.service
```

Read logs:

```bash
journalctl -u fe-daily-runner.service -n 200 --no-pager
journalctl -u fe-daily-runner.timer -n 100 --no-pager
```

If the production path is not `/home/dev/FE/services/FE-Daily-Runner`, edit
`WorkingDirectory` in `/etc/systemd/system/fe-daily-runner.service`.

## 7. Verification Checklist

Run after every deployment:

```bash
docker network inspect fe-shared >/dev/null

cd /home/dev/FE/services/fe-question-bank-service
docker compose --env-file .env ps
curl -fsS http://127.0.0.1:8000/health

cd /home/dev/FE/services/FE-telegram-bot
docker compose --env-file .env -f deploy/docker-compose.yml ps
curl -fsS http://127.0.0.1:3100/quiz/invalid-token >/tmp/fe-quiz-smoke.html
wc -c /tmp/fe-quiz-smoke.html

cd /home/dev/FE/services/FE-Daily-Runner
docker compose run --rm fe-daily-runner python scripts/daily_publish.py --validate-config
docker compose run --rm fe-daily-runner python scripts/daily_publish.py --health-check
docker compose run --rm fe-daily-runner python scripts/daily_publish.py --today --dry-run
```

Public checks:

```bash
curl -fsS https://example.com/quiz/invalid-token >/tmp/fe-quiz-public.html
curl -fsS https://example.com/daily/ >/tmp/fe-daily-public.html
```

Expected containers:

```text
question-bank-runtime
deploy-edge-1
deploy-web-1
deploy-bot-1
```

Daily Runner normally runs as a short-lived container only when invoked by
systemd or a manual `docker compose run`.

## 8. Backups

Back up these paths at minimum:

```text
/home/dev/FE/services/fe-question-bank-service/.env
/opt/fe-question-bank/data/fe_siken_questions.sqlite
/opt/fe-question-bank/data/question_keyword_taxonomy.json
/opt/fe-question-bank/data/question_topic_mappings.json
/opt/fe-question-bank/public/assets/fe-siken/

/home/dev/FE/services/FE-telegram-bot/.env
/home/dev/FE/services/FE-telegram-bot/config/app.yaml
/home/dev/FE/services/FE-telegram-bot/data/app.sqlite
/home/dev/FE/services/FE-telegram-bot/data/fe_siken_questions.sqlite
/home/dev/FE/services/FE-telegram-bot/logs/

/home/dev/FE/services/FE-Daily-Runner/.env
/home/dev/FE/services/FE-Daily-Runner/references/
/home/dev/FE/services/FE-Daily-Runner/personal/
/home/dev/FE/services/FE-Daily-Runner/state/
/home/dev/FE/services/FE-Daily-Runner/logs/
/var/www/example-daily/
```

For SQLite, take a consistent backup. Example:

```bash
sqlite3 /home/dev/FE/services/FE-telegram-bot/data/app.sqlite ".backup '/backup/fe-app-$(date +%F).sqlite'"
sqlite3 /opt/fe-question-bank/data/fe_siken_questions.sqlite ".backup '/backup/fe-question-bank-$(date +%F).sqlite'"
```

## 9. Update Procedure

For code updates:

```bash
cd /home/dev/FE/services/fe-question-bank-service
git pull
docker compose --env-file .env up -d --build question-bank-runtime
curl -fsS http://127.0.0.1:8000/health

cd /home/dev/FE/services/FE-telegram-bot
git pull
docker compose --env-file .env -f deploy/docker-compose.yml --profile tools run --rm migrate
docker compose --env-file .env -f deploy/docker-compose.yml up -d --build edge web bot
docker compose --env-file .env -f deploy/docker-compose.yml restart edge

cd /home/dev/FE/services/FE-Daily-Runner
git pull
docker compose build fe-daily-runner
docker compose run --rm fe-daily-runner python scripts/daily_publish.py --health-check
```

Then run the verification checklist.

## 10. Common Failures

`question-bank-runtime` health check fails:

- Confirm `fe_siken_questions.sqlite` exists in `HOST_DATA_DIR`.
- Confirm keyword JSON files exist in the same runtime data directory.
- Confirm the `fe-shared` network exists.

Telegram web page returns `502`:

- Check `docker compose ps` under `FE-telegram-bot`.
- Restart `edge` after rebuilding `web` or `bot`.
- Confirm host Nginx proxies to `127.0.0.1:3100`.

Daily page is generated but public URL is `404`:

- Confirm `HOST_STATIC_PUBLISH_DIR` or Compose default points to the same path
  used by Nginx `alias /var/www/example-daily/`.
- Confirm Nginx `location /daily/` uses `alias`, not `root`.

Telegram message link is wrong:

- Check `FE-Daily-Runner/.env` `PAGE_BASE_URL`.
- It should normally be `https://example.com/daily`, not
  `https://example.com/daily/daily`.

Webhook registration fails:

- Confirm `PUBLIC_BASE_URL` is the HTTPS origin.
- Confirm `TELEGRAM_WEBHOOK_PATH_SECRET` and
  `TELEGRAM_WEBHOOK_SECRET_TOKEN` are present.
- Confirm `/telegram/webhook/` is proxied by VPS Nginx.

## 11. Security Notes

- Bind Docker-published internal ports to `127.0.0.1` unless intentionally exposing them.
- Keep `question-bank-admin` stopped except during maintenance.
- Store `.env` with restricted permissions:

```bash
chmod 600 /home/dev/FE/services/fe-question-bank-service/.env
chmod 600 /home/dev/FE/services/FE-telegram-bot/.env
chmod 600 /home/dev/FE/services/FE-Daily-Runner/.env
```

- Do not add `.env`, generated state, private keys, or real tokens to Git.
- Rotate OpenAI and Telegram credentials if they were ever pasted into logs,
  commits, issue trackers, or chat messages.
