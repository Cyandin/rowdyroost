#!/usr/bin/env bash
set -Eeuo pipefail

STACK="${1:-}"

DOCKER_ROOT="${HOME}/docker"
BACKUP_ROOT="${HOME}/docker-backups"

case "${STACK}" in
  dns-stack|infra-stack|proxy-stack|plex-stack)
    ;;
  *)
    echo "ERROR: Usage: $0 {dns-stack|infra-stack|proxy-stack|plex-stack}"
    exit 1
    ;;
esac

STACK_DIR="${DOCKER_ROOT}/${STACK}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${STACK}/${TIMESTAMP}"

if [[ ! -d "${STACK_DIR}" ]]; then
  echo "ERROR: Stack directory does not exist:"
  echo "  ${STACK_DIR}"
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

echo "========================================"
echo "Backing up production stack: ${STACK}"
echo "Source:      ${STACK_DIR}"
echo "Destination: ${BACKUP_DIR}"
echo "========================================"

if [[ "${STACK}" != "plex-stack" ]]; then
  echo
  echo "Checking sudo access..."
  sudo -v
fi

cd "${STACK_DIR}"

docker compose config > "${BACKUP_DIR}/compose-resolved.yaml"
docker compose config --images > "${BACKUP_DIR}/images.txt"
docker compose ps > "${BACKUP_DIR}/compose-ps.txt"

docker ps \
  --format '{{.Names}}|{{.Image}}|{{.ID}}|{{.Status}}' \
  > "${BACKUP_DIR}/docker-containers.txt"

{
  while IFS= read -r container; do
    [[ -z "${container}" ]] && continue

    echo "=== ${container} ==="

    docker inspect "${container}" \
      --format 'ContainerImage={{.Config.Image}} ImageID={{.Image}}'

    image_id="$(docker inspect "${container}" --format '{{.Image}}')"

    docker image inspect "${image_id}" \
      --format '{{range .RepoDigests}}{{println .}}{{end}}' \
      2>/dev/null || true

    echo
  done < <(docker compose ps --format '{{.Name}}')
} > "${BACKUP_DIR}/image-state.txt"

case "${STACK}" in

  dns-stack)
    cp -a \
      "${STACK_DIR}/docker-compose.yaml" \
      "${BACKUP_DIR}/docker-compose.yaml"

    sudo cp -a \
      "${STACK_DIR}/adguard" \
      "${BACKUP_DIR}/adguard"
    ;;

  infra-stack)
    cp -a \
      "${STACK_DIR}/docker-compose.yaml" \
      "${BACKUP_DIR}/docker-compose.yaml"

    if [[ -f "${STACK_DIR}/.env" ]]; then
      cp -a \
        "${STACK_DIR}/.env" \
        "${BACKUP_DIR}/.env"
    fi

    sudo cp -a \
      "${STACK_DIR}/homeassistant" \
      "${BACKUP_DIR}/homeassistant"

    sudo cp -a \
      "${STACK_DIR}/homarr" \
      "${BACKUP_DIR}/homarr"

    sudo cp -a \
      "${STACK_DIR}/uptime-kuma" \
      "${BACKUP_DIR}/uptime-kuma"
    ;;

  proxy-stack)
    cp -a \
      "${STACK_DIR}/docker-compose.yaml" \
      "${BACKUP_DIR}/docker-compose.yaml"

    sudo cp -a \
      "${STACK_DIR}/data" \
      "${BACKUP_DIR}/data"

    sudo cp -a \
      "${STACK_DIR}/letsencrypt" \
      "${BACKUP_DIR}/letsencrypt"
    ;;

  plex-stack)
    cp -a \
      "${STACK_DIR}/docker-compose.yml" \
      "${BACKUP_DIR}/docker-compose.yml"

    if [[ -f "${STACK_DIR}/.env" ]]; then
      cp -a \
        "${STACK_DIR}/.env" \
        "${BACKUP_DIR}/.env"
    fi

    APPDATA_ROOT="${HOME}/docker/appdata"

    for dir in \
      gluetun \
      qbittorrent \
      plex \
      radarr \
      sonarr \
      prowlarr
    do
      if [[ -d "${APPDATA_ROOT}/${dir}" ]]; then
        cp -a \
          "${APPDATA_ROOT}/${dir}" \
          "${BACKUP_DIR}/${dir}"
      fi
    done
    ;;
esac

if [[ "${STACK}" != "plex-stack" ]]; then
  sudo chown -R "${USER}:${USER}" "${BACKUP_DIR}"
fi

chmod -R go-rwx "${BACKUP_DIR}"

echo
echo "========================================"
echo "Backup complete"
echo "========================================"

du -sh "${BACKUP_DIR}"

echo
echo "Backup location:"
echo "${BACKUP_DIR}"
