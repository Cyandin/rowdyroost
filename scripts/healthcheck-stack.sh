#!/usr/bin/env bash
set -Eeuo pipefail

STACK="${1:-}"

case "${STACK}" in
  dns-stack|infra-stack|proxy-stack|plex-stack)
    ;;
  *)
    echo "ERROR: Usage: $0 {dns-stack|infra-stack|proxy-stack|plex-stack}"
    exit 1
    ;;
esac

PASS=0
FAIL=0

RETRIES=6
RETRY_DELAY=5

check_http() {
  local name="$1"
  local url="$2"

  echo -n "Checking ${name} ... "

  for attempt in $(seq 1 "${RETRIES}"); do
    if curl -fsS \
      --connect-timeout 5 \
      --max-time 15 \
      "${url}" >/dev/null; then

      echo "PASS"
      PASS=$((PASS + 1))
      return 0
    fi

    if [[ "${attempt}" -lt "${RETRIES}" ]]; then
      sleep "${RETRY_DELAY}"
    fi
  done

  echo "FAIL"
  FAIL=$((FAIL + 1))
}

check_http_reachable() {
  local name="$1"
  local url="$2"

  echo -n "Checking ${name} ... "

  local status=""

  for attempt in $(seq 1 "${RETRIES}"); do
    status="$(
      curl -sS \
        --connect-timeout 5 \
        --max-time 15 \
        -o /dev/null \
        -w '%{http_code}' \
        "${url}" \
        || true
    )"

    if [[ "${status}" =~ ^[1-4][0-9][0-9]$ ]]; then
      echo "PASS (HTTP ${status})"
      PASS=$((PASS + 1))
      return 0
    fi

    if [[ "${attempt}" -lt "${RETRIES}" ]]; then
      sleep "${RETRY_DELAY}"
    fi
  done

  echo "FAIL (HTTP ${status:-none})"
  FAIL=$((FAIL + 1))
}

check_http_resolve() {
  local name="$1"
  local url="$2"
  local resolve="$3"

  echo -n "Checking ${name} ... "

  for attempt in $(seq 1 "${RETRIES}"); do
    if curl -fsS \
      --connect-timeout 5 \
      --max-time 15 \
      --resolve "${resolve}" \
      "${url}" >/dev/null; then

      echo "PASS"
      PASS=$((PASS + 1))
      return 0
    fi

    if [[ "${attempt}" -lt "${RETRIES}" ]]; then
      sleep "${RETRY_DELAY}"
    fi
  done

  echo "FAIL"
  FAIL=$((FAIL + 1))
}

check_http_reachable_resolve() {
  local name="$1"
  local url="$2"
  local resolve="$3"

  echo -n "Checking ${name} ... "

  local status=""

  for attempt in $(seq 1 "${RETRIES}"); do
    status="$(
      curl -sS \
        --connect-timeout 5 \
        --max-time 15 \
        --resolve "${resolve}" \
        -o /dev/null \
        -w '%{http_code}' \
        "${url}" \
        || true
    )"

    if [[ "${status}" =~ ^[1-4][0-9][0-9]$ ]]; then
      echo "PASS (HTTP ${status})"
      PASS=$((PASS + 1))
      return 0
    fi

    if [[ "${attempt}" -lt "${RETRIES}" ]]; then
      sleep "${RETRY_DELAY}"
    fi
  done

  echo "FAIL (HTTP ${status:-none})"
  FAIL=$((FAIL + 1))
}

check_tcp() {
  local name="$1"
  local host="$2"
  local port="$3"

  echo -n "Checking ${name} ... "

  for attempt in $(seq 1 "${RETRIES}"); do
    if timeout 5 bash -c \
      "</dev/tcp/${host}/${port}" 2>/dev/null; then

      echo "PASS"
      PASS=$((PASS + 1))
      return 0
    fi

    if [[ "${attempt}" -lt "${RETRIES}" ]]; then
      sleep "${RETRY_DELAY}"
    fi
  done

  echo "FAIL"
  FAIL=$((FAIL + 1))
}

check_container() {
  local name="$1"

  echo -n "Checking container ${name} ... "

  for attempt in $(seq 1 "${RETRIES}"); do
    if docker inspect "${name}" \
      --format '{{.State.Running}}' \
      2>/dev/null | grep -q '^true$'; then

      echo "PASS"
      PASS=$((PASS + 1))
      return 0
    fi

    if [[ "${attempt}" -lt "${RETRIES}" ]]; then
      sleep "${RETRY_DELAY}"
    fi
  done

  echo "FAIL"
  FAIL=$((FAIL + 1))
}

check_container_healthy() {
  local name="$1"

  echo -n "Checking container health ${name} ... "

  for attempt in $(seq 1 "${RETRIES}"); do
    local status

    status="$(
      docker inspect "${name}" \
        --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        2>/dev/null \
        || true
    )"

    if [[ "${status}" == "healthy" ]]; then
      echo "PASS"
      PASS=$((PASS + 1))
      return 0
    fi

    if [[ "${attempt}" -lt "${RETRIES}" ]]; then
      sleep "${RETRY_DELAY}"
    fi
  done

  echo "FAIL"
  FAIL=$((FAIL + 1))
}

check_vpn_egress() {
  echo -n "Checking VPN internet egress ... "

  for attempt in $(seq 1 "${RETRIES}"); do
    local vpn_ip

    vpn_ip="$(
      docker exec vpn \
        wget -qO- https://ipinfo.io/ip \
        2>/dev/null \
        || true
    )"

    if [[ "${vpn_ip}" =~ ^[0-9a-fA-F:.]+$ ]]; then
      echo "PASS (${vpn_ip})"
      PASS=$((PASS + 1))
      return 0
    fi

    if [[ "${attempt}" -lt "${RETRIES}" ]]; then
      sleep "${RETRY_DELAY}"
    fi
  done

  echo "FAIL"
  FAIL=$((FAIL + 1))
}

echo "========================================"
echo "Health check: ${STACK}"
echo "========================================"

case "${STACK}" in

  dns-stack)
    check_container adguardhome

    check_tcp \
      "AdGuard DNS TCP" \
      "192.168.1.174" \
      "53"

    echo -n "Checking DNS resolution through AdGuard ... "

    dns_ok=false

    for attempt in $(seq 1 "${RETRIES}"); do
      if dig @192.168.1.174 example.com +short | grep -q .; then
        dns_ok=true
        break
      fi

      if [[ "${attempt}" -lt "${RETRIES}" ]]; then
        sleep "${RETRY_DELAY}"
      fi
    done

    if [[ "${dns_ok}" == "true" ]]; then
      echo "PASS"
      PASS=$((PASS + 1))
    else
      echo "FAIL"
      FAIL=$((FAIL + 1))
    fi

    check_http \
      "AdGuard Web UI" \
      "http://192.168.1.174:8002"
    ;;

  infra-stack)
    check_container homeassistant
    check_container homarr
    check_container uptime-kuma
    check_container cloudflared

    check_http_resolve \
      "Home Assistant through NPM" \
      "http://hq.home.arpa" \
      "hq.home.arpa:80:192.168.1.174"

    check_http_resolve \
      "Homarr through NPM" \
      "http://homarr.home.arpa" \
      "homarr.home.arpa:80:192.168.1.174"

    check_http_resolve \
      "Uptime Kuma through NPM" \
      "http://status.home.arpa" \
      "status.home.arpa:80:192.168.1.174"

    check_http \
      "External Home Assistant" \
      "https://hq.therowdyroost.com"
    ;;

  proxy-stack)
    check_container nginx-proxy-manager

    check_http_resolve \
      "NPM Admin" \
      "http://npm.home.arpa" \
      "npm.home.arpa:80:192.168.1.174"

    check_http_resolve \
      "Home Assistant through NPM" \
      "http://hq.home.arpa" \
      "hq.home.arpa:80:192.168.1.174"

    check_http_reachable_resolve \
      "Plex through NPM" \
      "http://plex.home.arpa" \
      "plex.home.arpa:80:192.168.1.174"
    ;;

  plex-stack)
    #
    # Container-level checks
    #
    check_container_healthy vpn
    check_container qbittorrent
    check_container plex
    check_container radarr
    check_container sonarr
    check_container prowlarr
    check_container flaresolverr

    #
    # Verify the VPN namespace actually has outbound connectivity.
    #
    check_vpn_egress

    #
    # Gluetun health endpoint.
    #
    check_http \
      "Gluetun health endpoint" \
      "http://127.0.0.1:9999"

    #
    # qBittorrent shares Gluetun's network namespace.
    # An authentication response is acceptable here; we're verifying
    # that the service is reachable through the published Gluetun port.
    #
    check_http_reachable \
      "qBittorrent Web UI" \
      "http://127.0.0.1:8080"

    #
    # Plex may return an authentication response when queried without
    # a Plex token, so any HTTP 1xx-4xx response proves reachability.
    #
    check_http_reachable \
      "Plex" \
      "http://127.0.0.1:32400/web"

    check_http_reachable \
      "Radarr" \
      "http://127.0.0.1:7878"

    check_http_reachable \
      "Sonarr" \
      "http://127.0.0.1:8989"

    check_http_reachable \
      "Prowlarr" \
      "http://127.0.0.1:9696"

    check_http_reachable \
      "FlareSolverr" \
      "http://127.0.0.1:8191"
    ;;
esac

echo
echo "========================================"
echo "PASS: ${PASS}"
echo "FAIL: ${FAIL}"
echo "========================================"

if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi

exit 0
