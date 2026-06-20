# FE Integrated Deployment Repository

This repository is the operations wrapper for the FE study system. It does not
replace the three application repositories; it keeps them under `services/` and
provides one place for deployment documentation, host-level deploy assets, and
repeatable scripts.

## Overall Goal

Deploy and operate the complete FE learning stack on one VPS:

- Serve FE question-bank data and cached image assets.
- Run the Telegram quiz web app and webhook bot.
- Generate the daily study page, publish it as static HTML, and push the page
  link to Telegram on a schedule.

## Service Responsibilities

| Service | Path | Responsibility |
|---|---|---|
| Question Bank Runtime | `services/fe-question-bank-service` | FastAPI runtime for FE question SQLite data, keyword metadata, and cached question images. Other containers call it through `http://question-bank-runtime:8000` on the shared Docker network. |
| Telegram Quiz Bot | `services/FE-telegram-bot` | Next.js quiz web app, Telegram webhook bot, database migration task, and Docker edge Nginx published on `127.0.0.1:3100`. |
| Daily Runner | `services/FE-Daily-Runner` | Python workflow that reads study context, selects questions from the runtime, asks OpenAI for page content, renders static daily pages, copies them to the public static directory, and optionally sends Telegram notifications. |

## Repository Layout

```text
.
├── README.md
├── repos.yaml
├── deploy/
│   ├── artifacts/
│   ├── nginx/
│   └── systemd/
├── docs/
├── scripts/
└── services/
    ├── FE-Daily-Runner/
    ├── FE-telegram-bot/
    └── fe-question-bank-service/
```

## Quick Start

1. Pull or clone service repositories:

```bash
./scripts/pull-repos.sh
```

2. Create production `.env` files in each service directory. Use the example
   files in each service as a starting point. Do not commit real secrets.

3. Deploy in dependency order:

```bash
./scripts/deploy-all.sh
```

4. Install host Nginx and systemd files from `deploy/` as described in:

```text
docs/production-deployment.md
```

## Important Files

- `repos.yaml`: upstream Git repositories and local service paths.
- `deploy/nginx/`: host-level Nginx configuration examples.
- `deploy/systemd/`: systemd timer/service for Daily Runner.
- `docs/production-deployment.md`: full production deployment guide.
- `docs/deployment-missing-requirements.md`: last deployment validation status.
- `scripts/pull-repos.sh`: clone or update all service repositories.
- `scripts/install-assets.sh`: install `deploy/artifacts/public.zip` into the
  question-bank `HOST_ASSET_DIR` from its `.env`.
- `scripts/deploy-all.sh`: deploy and validate all Docker services.

## Secret Handling

Keep these out of Git:

- `services/*/.env`
- OpenAI API keys
- Telegram bot tokens and webhook secrets
- SSH private keys
- SQLite WAL/SHM files
- generated runtime logs and state

If a secret is accidentally committed or published, rotate it before deploying
to production.
