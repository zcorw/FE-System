# Docker Deployment Requirements Status

Updated at: 2026-06-18 00:05 JST

## Summary

All previously missing runtime inputs have been added locally and Docker deployment validation has passed.

No required deployment content is currently missing.

Sensitive files created during this run:

- `FE-telegram-bot/.env`
- `FE-Daily-Runner/.env`

These contain real secrets and must not be committed.

## fe-question-bank-service

Status: deployed and healthy.

Running container:

- `question-bank-runtime`

Verification:

- `docker compose up -d --build question-bank-runtime`: passed
- `curl -fsS http://127.0.0.1:8000/health`: returned `{"ok":true,"database":"ready","readOnly":true}`

Runtime endpoint:

- `http://127.0.0.1:8000`

## FE-telegram-bot

Status: deployed.

Running containers:

- `deploy-web-1`
- `deploy-bot-1`
- `deploy-edge-1`

Files added:

- `FE-telegram-bot/.env`

Verification:

- `docker compose --env-file .env -f deploy/docker-compose.yml --profile tools run --rm migrate`: passed
- `docker compose --env-file .env -f deploy/docker-compose.yml up -d edge web bot`: passed
- `docker compose --env-file .env -f deploy/docker-compose.yml ps`: showed `edge`, `web`, and `bot` running
- `curl -fsS http://127.0.0.1:3100/quiz/invalid-token -o /tmp/fe-quiz-smoke.html`: passed
- `wc -c /tmp/fe-quiz-smoke.html`: `7900 /tmp/fe-quiz-smoke.html`

Runtime endpoint:

- `http://127.0.0.1:3100`

Operational note:

- `edge` was restarted after `web` was recreated because Nginx had cached the old `web` container IP and briefly returned `502`.

## FE-Daily-Runner

Status: deployed and dry-run verified.

Files added:

- `FE-Daily-Runner/.env`
- `FE-Daily-Runner/references/legacy-project/june-study-plan.md`
- `FE-Daily-Runner/references/personal-context/weak_points.md`
- `FE-Daily-Runner/references/personal-context/mistake_log.md`
- `FE-Daily-Runner/references/personal-context/progress.md`

Code compatibility fix:

- `FE-Daily-Runner/src/fe_daily/question_details.py`: Runtime details no longer require precomputed `distractor_explanations`.
- `FE-Daily-Runner/src/fe_daily/workflow.py`: missing distractor explanations are filled with deterministic Japanese fallback text per wrong answer choice.

Verification:

- `docker compose build fe-daily-runner`: passed
- `docker compose run --rm fe-daily-runner python scripts/daily_publish.py --validate-config`: passed
- `docker compose run --rm fe-daily-runner python scripts/daily_publish.py --health-check`: returned `question bank runtime is healthy`
- `docker compose run --rm fe-daily-runner python scripts/daily_publish.py --today --dry-run`: returned `Workflow success: 2026-06-18`

Dry-run outputs:

- `FE-Daily-Runner/site/tmp/dry-run/2026-06-18/preview.html`
- `FE-Daily-Runner/site/tmp/dry-run/2026-06-18/raw-openai-output.json`
- `FE-Daily-Runner/site/tmp/dry-run/2026-06-18/validated-output.json`

Unit verification for compatibility fix:

- `/tmp/fe-daily-venv/bin/pytest tests/test_question_details.py tests/test_workflow.py::test_question_block_generates_fallback_distractor_explanations_when_runtime_omits_them -q`: `9 passed, 1 warning`

## Final Container State

Observed with `docker ps`:

```text
NAMES                   IMAGE                             STATUS                    PORTS
deploy-bot-1            fe-telegram-bot-bot:local         Up                         3001/tcp
deploy-web-1            fe-telegram-bot-web:local         Up                         3000/tcp
question-bank-runtime   fe-question-bank-service:latest   Up (healthy)               127.0.0.1:8000->8000/tcp
deploy-edge-1           nginx:1.27-alpine                 Up                         80/tcp, 127.0.0.1:3100->8080/tcp
```
