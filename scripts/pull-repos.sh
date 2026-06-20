#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

clone_or_update() {
  local name="$1"
  local repo="$2"
  local branch="$3"
  local path="$4"

  local target="${ROOT_DIR}/${path}"
  mkdir -p "$(dirname "${target}")"

  if [[ -d "${target}/.git" ]]; then
    echo "==> Updating ${name} (${path})"
    git -C "${target}" fetch origin
    local current_branch
    current_branch="$(git -C "${target}" branch --show-current)"
    if [[ "${current_branch}" != "${branch}" ]]; then
      git -C "${target}" checkout "${branch}"
    fi
    git -C "${target}" pull --ff-only origin "${branch}"
  elif [[ -e "${target}" ]]; then
    echo "ERROR: ${target} exists but is not a Git repository" >&2
    exit 1
  else
    echo "==> Cloning ${name} into ${path}"
    git clone --branch "${branch}" "${repo}" "${target}"
  fi
}

clone_or_update "fe-question-bank-service" \
  "git@github.com:zcorw/fe-question-bank-service.git" \
  "feat/question-bank-service" \
  "services/fe-question-bank-service"

clone_or_update "FE-telegram-bot" \
  "git@github.com:zcorw/fe-siken-quiz-bot.git" \
  "main" \
  "services/FE-telegram-bot"

clone_or_update "FE-Daily-Runner" \
  "git@github.com:zcorw/FE-Daily-Runner-Python.git" \
  "feat/runtime-question-explanations" \
  "services/FE-Daily-Runner"

echo "All service repositories are present under ${ROOT_DIR}/services."
