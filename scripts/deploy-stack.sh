#!/usr/bin/env bash
set -Eeuo pipefail

STACK="${1:-}"

REPO_ROOT="${HOME}/rowdyroost"
DOCKER_ROOT="${HOME}/docker"
BACKUP_ROOT="${HOME}/docker-backups"

BACKUP_SCRIPT="${REPO_ROOT}/scripts/backup-stack.sh"
HEALTHCHECK_SCRIPT="${REPO_ROOT}/scripts/healthcheck-stack.sh"
ROLLBACK_SCRIPT="${REPO_ROOT}/scripts/rollback-stack.sh"

case "${STACK}" in
  dns-stack|infra-stack|proxy-stack|plex-stack)
    ;;
  *)
    echo "ERROR: Usage: $0 {dns-stack|infra-stack|proxy-stack|plex-stack}"
    exit 1
    ;;
esac

REPO_STACK="${REPO_ROOT}/${STACK}"
LIVE_STACK="${DOCKER_ROOT}/${STACK}"

if [[ "${STACK}" == "plex-stack" ]]; then
  COMPOSE_FILE="docker-compose.yml"
else
  COMPOSE_FILE="docker-compose.yaml"
fi

echo "========================================"
echo "PRODUCTION DEPLOYMENT"
echo "========================================"
echo "Stack: ${STACK}"
echo

echo "Running pre-deployment health check..."

if ! "${HEALTHCHECK_SCRIPT}" "${STACK}"; then
  echo
  echo "ERROR: Current production stack is already unhealthy."
  echo "Deployment aborted."
  exit 1
fi

echo
echo "Creating pre-deployment backup..."

"${BACKUP_SCRIPT}" "${STACK}"

LATEST_BACKUP="$(
  find "${BACKUP_ROOT}/${STACK}" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    | sort \
    | tail -1
)"

if [[ -z "${LATEST_BACKUP}" || ! -d "${LATEST_BACKUP}" ]]; then
  echo "ERROR: Could not determine pre-deployment backup."
  exit 1
fi

BACKUP_ID="$(basename "${LATEST_BACKUP}")"

echo
echo "Pre-deployment backup:"
echo "  ${LATEST_BACKUP}"

echo
echo "Validating approved Compose configuration..."

if [[ "${STACK}" == "infra-stack" ]]; then
  docker compose \
    -f "${REPO_STACK}/${COMPOSE_FILE}" \
    --env-file "${LIVE_STACK}/.env" \
    config >/dev/null
elif [[ "${STACK}" == "plex-stack" && -f "${LIVE_STACK}/.env" ]]; then
  docker compose \
    -f "${REPO_STACK}/${COMPOSE_FILE}" \
    --env-file "${LIVE_STACK}/.env" \
    config >/dev/null
else
  docker compose \
    -f "${REPO_STACK}/${COMPOSE_FILE}" \
    config >/dev/null
fi

echo "Compose validation passed."

echo
echo "Syncing approved Compose definition to production..."

cp \
  "${REPO_STACK}/${COMPOSE_FILE}" \
  "${LIVE_STACK}/${COMPOSE_FILE}"

echo
echo "Pulling approved images..."

cd "${LIVE_STACK}"
docker compose pull

echo
echo "Deploying stack..."

docker compose up -d

echo
echo "Running post-deployment health checks..."

if "${HEALTHCHECK_SCRIPT}" "${STACK}"; then
  echo
  echo "========================================"
  echo "DEPLOYMENT SUCCESSFUL"
  echo "========================================"
  echo "Stack: ${STACK}"
  echo "Rollback point: ${BACKUP_ID}"
  exit 0
fi

echo
echo "========================================"
echo "DEPLOYMENT FAILED HEALTH CHECKS"
echo "========================================"
echo
echo "Automatic rollback will begin."
echo "Rollback point: ${BACKUP_ID}"
echo

"${ROLLBACK_SCRIPT}" \
  "${STACK}" \
  "${BACKUP_ID}" \
  --automatic
