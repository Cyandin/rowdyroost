#!/usr/bin/env bash
set -Eeuo pipefail

STACK="${1:-}"
BACKUP_ID="${2:-latest}"
MODE="${3:-manual}"

DOCKER_ROOT="${HOME}/docker"
BACKUP_ROOT="${HOME}/docker-backups"
HEALTHCHECK_SCRIPT="${HOME}/rowdyroost/scripts/healthcheck-stack.sh"

case "${STACK}" in
  dns-stack|infra-stack|proxy-stack)
    ;;
  *)
    echo "ERROR: Usage: $0 {dns-stack|infra-stack|proxy-stack} [backup-id|latest] [manual|--automatic]"
    exit 1
    ;;
esac

if [[ "${MODE}" != "manual" && "${MODE}" != "--automatic" ]]; then
  echo "ERROR: Third argument must be 'manual' or '--automatic'"
  exit 1
fi

STACK_DIR="${DOCKER_ROOT}/${STACK}"
STACK_BACKUP_ROOT="${BACKUP_ROOT}/${STACK}"

if [[ ! -d "${STACK_DIR}" ]]; then
  echo "ERROR: Live stack directory not found:"
  echo "  ${STACK_DIR}"
  exit 1
fi

if [[ ! -d "${STACK_BACKUP_ROOT}" ]]; then
  echo "ERROR: No backups found for ${STACK}"
  exit 1
fi

if [[ "${BACKUP_ID}" == "latest" ]]; then
  BACKUP_DIR="$(
    find "${STACK_BACKUP_ROOT}" \
      -mindepth 1 \
      -maxdepth 1 \
      -type d \
      | sort \
      | tail -1
  )"
else
  BACKUP_DIR="${STACK_BACKUP_ROOT}/${BACKUP_ID}"
fi

if [[ -z "${BACKUP_DIR}" || ! -d "${BACKUP_DIR}" ]]; then
  echo "ERROR: Backup not found:"
  echo "  ${BACKUP_DIR}"
  exit 1
fi

if [[ ! -f "${BACKUP_DIR}/docker-compose.yaml" ]]; then
  echo "ERROR: Backup does not contain docker-compose.yaml"
  exit 1
fi

echo "========================================"
echo "ROLLBACK REQUESTED"
echo "========================================"
echo "Stack:  ${STACK}"
echo "Backup: ${BACKUP_DIR}"
echo "Mode:   ${MODE}"
echo
echo "This will:"
echo "  1. Stop the current ${STACK} containers"
echo "  2. Restore Compose and persistent data from backup"
echo "  3. Restart the stack"
echo "  4. Run production health checks"
echo

if [[ "${MODE}" != "--automatic" ]]; then
  read -r -p "Type ROLLBACK to continue: " CONFIRM

  if [[ "${CONFIRM}" != "ROLLBACK" ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

echo
echo "Checking sudo access..."
sudo -v

echo
echo "Stopping current stack..."

cd "${STACK_DIR}"
docker compose down

echo
echo "Restoring stack..."

case "${STACK}" in

  dns-stack)
    sudo rm -rf "${STACK_DIR}/adguard"

    sudo cp -a \
      "${BACKUP_DIR}/adguard" \
      "${STACK_DIR}/adguard"

    cp -a \
      "${BACKUP_DIR}/docker-compose.yaml" \
      "${STACK_DIR}/docker-compose.yaml"
    ;;

  infra-stack)
    sudo rm -rf \
      "${STACK_DIR}/homeassistant" \
      "${STACK_DIR}/homarr" \
      "${STACK_DIR}/uptime-kuma"

    sudo cp -a \
      "${BACKUP_DIR}/homeassistant" \
      "${STACK_DIR}/homeassistant"

    sudo cp -a \
      "${BACKUP_DIR}/homarr" \
      "${STACK_DIR}/homarr"

    sudo cp -a \
      "${BACKUP_DIR}/uptime-kuma" \
      "${STACK_DIR}/uptime-kuma"

    cp -a \
      "${BACKUP_DIR}/docker-compose.yaml" \
      "${STACK_DIR}/docker-compose.yaml"

    if [[ -f "${BACKUP_DIR}/.env" ]]; then
      cp -a \
        "${BACKUP_DIR}/.env" \
        "${STACK_DIR}/.env"
    fi
    ;;

  proxy-stack)
    sudo rm -rf \
      "${STACK_DIR}/data" \
      "${STACK_DIR}/letsencrypt"

    sudo cp -a \
      "${BACKUP_DIR}/data" \
      "${STACK_DIR}/data"

    sudo cp -a \
      "${BACKUP_DIR}/letsencrypt" \
      "${STACK_DIR}/letsencrypt"

    cp -a \
      "${BACKUP_DIR}/docker-compose.yaml" \
      "${STACK_DIR}/docker-compose.yaml"
    ;;
esac

echo
echo "Restored files from:"
echo "  ${BACKUP_DIR}"

echo
echo "Starting restored stack..."

cd "${STACK_DIR}"

docker compose pull
docker compose up -d

echo
echo "Waiting 20 seconds for services to initialize..."
sleep 20

echo
echo "Running production health checks..."

if "${HEALTHCHECK_SCRIPT}" "${STACK}"; then
  echo
  echo "========================================"
  echo "ROLLBACK SUCCESSFUL"
  echo "========================================"
  echo "Stack: ${STACK}"
  echo "Backup restored: ${BACKUP_DIR}"
  exit 0
else
  echo
  echo "========================================"
  echo "ROLLBACK COMPLETED BUT HEALTH CHECK FAILED"
  echo "========================================"
  echo
  echo "Manual intervention is required."
  echo "Backup used:"
  echo "  ${BACKUP_DIR}"
  exit 1
fi
