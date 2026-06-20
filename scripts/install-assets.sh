#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_ENV_FILE="${ROOT_DIR}/services/fe-question-bank-service/.env"
DEFAULT_ARCHIVE="${ROOT_DIR}/deploy/artifacts/public.zip"

usage() {
  cat <<'EOF'
Usage:
  scripts/install-assets.sh [ENV_FILE] [ASSET_ARCHIVE]

Defaults:
  ENV_FILE      services/fe-question-bank-service/.env
  ASSET_ARCHIVE deploy/artifacts/public.zip

The script reads HOST_ASSET_DIR from ENV_FILE and installs the contents of
assets/fe-siken/ from ASSET_ARCHIVE into that directory.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ENV_FILE="${1:-${DEFAULT_ENV_FILE}}"
ASSET_ARCHIVE="${2:-${DEFAULT_ARCHIVE}}"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required file is missing: ${path}" >&2
    exit 1
  fi
}

require_command() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command is missing: ${name}" >&2
    exit 1
  fi
}

env_value() {
  local file="$1"
  local key="$2"
  awk -F= -v key="${key}" '
    $0 !~ /^[[:space:]]*#/ && $1 == key {
      sub(/^[^=]*=/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      gsub(/^"|"$/, "")
      gsub(/^'\''|'\''$/, "")
      print
      exit
    }
  ' "${file}"
}

resolve_path() {
  local path="$1"
  local base_dir="$2"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${base_dir}/${path}"
  fi
}

require_command unzip
require_file "${ENV_FILE}"
require_file "${ASSET_ARCHIVE}"

ENV_DIR="$(cd "$(dirname "${ENV_FILE}")" && pwd)"
HOST_ASSET_DIR="$(env_value "${ENV_FILE}" HOST_ASSET_DIR)"

if [[ -z "${HOST_ASSET_DIR}" ]]; then
  echo "ERROR: HOST_ASSET_DIR is not set in ${ENV_FILE}" >&2
  exit 1
fi

TARGET_DIR="$(resolve_path "${HOST_ASSET_DIR}" "${ENV_DIR}")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
ZIP_LIST="${TMP_DIR}/zip-list.txt"
unzip -Z1 "${ASSET_ARCHIVE}" > "${ZIP_LIST}"

if awk '
  $0 ~ /^\// || $0 ~ /(^|\/)\.\.(\/|$)/ { bad = 1 }
  END { exit bad ? 0 : 1 }
' "${ZIP_LIST}"; then
  echo "ERROR: archive contains unsafe absolute or parent-relative paths" >&2
  exit 1
fi

if ! grep -q '^assets/fe-siken/' "${ZIP_LIST}"; then
  echo "ERROR: archive does not contain assets/fe-siken/" >&2
  exit 1
fi

echo "==> Installing question image assets"
echo "Archive: ${ASSET_ARCHIVE}"
echo "Target:  ${TARGET_DIR}"

mkdir -p "${TARGET_DIR}"
unzip -q "${ASSET_ARCHIVE}" 'assets/fe-siken/*' -d "${TMP_DIR}"
cp -a "${TMP_DIR}/assets/fe-siken/." "${TARGET_DIR}/"

FILE_COUNT="$(find "${TARGET_DIR}" -type f | wc -l | tr -d ' ')"
echo "Installed assets under ${TARGET_DIR} (${FILE_COUNT} files total)."
