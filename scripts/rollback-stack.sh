#!/usr/bin/env bash
set -Eeuo pipefail

STACK="${1:-}"
BACKUP_ID="${2:-latest}"
MODE="${3:-manual}"

DOCKER_ROOT="${HOME}/docker"
BACKUP_ROOT="${HOME}/docker-backups"
HEALTHCHECK_SCRIPT="${HOME}/rowdyroost/scripts/healthcheck-stack.sh"

case "${STACK}" in
  dns-stack|infra-stack|proxy-stack|plex-stack)
    ;;
  *)
    echo "ERROR: Usage: $0 {dns-stack|infra-stack|proxy-stack|plex-stack} [backup-id|latest] [manual|--automatic]"
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

COMPOSE_FILE="docker-compose.yaml"

if [[ "${STACK}" == "plex-stack" ]]; then
  COMPOSE_FILE="docker-compose.yml"
fi

if [[ ! -f "${BACKUP_DIR}/${COMPOSE_FILE}" ]]; then
  echo "ERROR: Backup does not contain ${COMPOSE_FILE}"
  exit 1
fi

echo "========================================"
echo "ROLLBACK REQUESTED"
echo "========================================"
echo "Stack:  ${STACK}"
echo "Backup: ${BACKUP_DIR}"
echo "Mode:   ${MODE}"
echo

if [[ "${MODE}" != "--automatic" ]]; then
  read -r -p "Type ROLLBACK to continue: " CONFIRM

  if [[ "${CONFIRM}" != "ROLLBACK" ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

if [[ "${STACK}" != "plex-stack" ]]; then
  echo
  echo "Checking sudo access..."
  sudo -v
fi

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

    sudo cp -a "${BACKUP_DIR}/homeassistant" "${STACK_DIR}/homeassistant"
    sudo cp -a "${BACKUP_DIR}/homarr" "${STACK_DIR}/homarr"
    sudo cp -a "${BACKUP_DIR}/uptime-kuma" "${STACK_DIR}/uptime-kuma"

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

    sudo cp -a "${BACKUP_DIR}/data" "${STACK_DIR}/data"
    sudo cp -a "${BACKUP_DIR}/letsencrypt" "${STACK_DIR}/letsencrypt"

    cp -a \
      "${BACKUP_DIR}/docker-compose.yaml" \
      "${STACK_DIR}/docker-compose.yaml"
    ;;

  plex-stack)
    APPDATA_ROOT="${HOME}/docker/appdata"

    for dir in \
      gluetun \
      qbittorrent \
      plex \
      radarr \
      sonarr \
      prowlarr
    do
      rm -rf "${APPDATA_ROOT}/${dir}"

      if [[ -d "${BACKUP_DIR}/${dir}" ]]; then
        cp -a \
          "${BACKUP_DIR}/${dir}" \
          "${APPDATA_ROOT}/${dir}"
      fi
    done

    cp -a \
      "${BACKUP_DIR}/docker-compose.yml" \
      "${STACK_DIR}/docker-compose.yml"

    if [[ -f "${BACKUP_DIR}/.env" ]]; then
      cp -a \
        "${BACKUP_DIR}/.env" \
        "${STACK_DIR}/.env"
    fi
    ;;
esac

echo
echo "Starting restored stack..."

cd "${STACK_DIR}"
docker compose pull
docker compose up -d

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
  exit 1
fi
