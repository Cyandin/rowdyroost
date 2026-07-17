#!/usr/bin/env bash
set -Eeuo pipefail

STACK="${1:-}"

case "${STACK}" in
  dns-stack|infra-stack|proxy-stack)
    ;;
  *)
    echo "ERROR: Usage: $0 {dns-stack|infra-stack|proxy-stack}"
    exit 1
    ;;
esac

PASS=0
FAIL=0

check_http() {
  local name="$1"
  local url="$2"

  echo -n "Checking ${name} ... "

  if curl -fsS \
    --connect-timeout 5 \
    --max-time 15 \
    "${url}" >/dev/null; then

    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
}

check_http_resolve() {
  local name="$1"
  local url="$2"
  local resolve="$3"

  echo -n "Checking ${name} ... "

  if curl -fsS \
    --connect-timeout 5 \
    --max-time 15 \
    --resolve "${resolve}" \
    "${url}" >/dev/null; then

    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
}

check_http_reachable_resolve() {
  local name="$1"
  local url="$2"
  local resolve="$3"

  echo -n "Checking ${name} ... "

  local status

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
  else
    echo "FAIL (HTTP ${status:-none})"
    FAIL=$((FAIL + 1))
  fi
}

check_tcp() {
  local name="$1"
  local host="$2"
  local port="$3"

  echo -n "Checking ${name} ... "

  if timeout 5 bash -c \
    "</dev/tcp/${host}/${port}" 2>/dev/null; then

    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
}

check_container() {
  local name="$1"

  echo -n "Checking container ${name} ... "

  if docker inspect "${name}" \
    --format '{{.State.Running}}' \
    2>/dev/null | grep -q '^true$'; then

    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
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

    if dig @192.168.1.174 example.com +short | grep -q .; then
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
