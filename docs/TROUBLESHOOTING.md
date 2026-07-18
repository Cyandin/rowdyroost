# Troubleshooting

Symptom-first guides. Prefer repository scripts and addresses already used in Compose / health checks.

Related: [SCRIPTS.md](SCRIPTS.md) · [NETWORKING.md](NETWORKING.md) · [CONTAINERS.md](CONTAINERS.md)

**Always start with:** which host am I on, and which stack owns this symptom?

```bash
~/rowdyroost/scripts/healthcheck-stack.sh dns-stack
~/rowdyroost/scripts/healthcheck-stack.sh proxy-stack
~/rowdyroost/scripts/healthcheck-stack.sh infra-stack
~/rowdyroost/scripts/healthcheck-stack.sh plex-stack
```

---

## Nothing on the network resolves

**Symptoms:** Browsers fail for both internet and `home.arpa`; `dig` times out.

**Likely layer:** DNS (AdGuard on Blackblade), not Plex.

**Checks:**

```bash
# From a client
dig @192.168.1.174 example.com +short
~/rowdyroost/scripts/healthcheck-stack.sh dns-stack   # on Blackblade
docker ps --filter name=adguardhome
```

**Ideas:**

1. Is `adguardhome` running?
2. Is the client actually using `192.168.1.174` as DNS? (Router DHCP — outside repo.)
3. Can you ping `192.168.1.174`?
4. Host networking / port 53 conflict on Blackblade.

**Not the first suspect:** Radarr, qBittorrent, Renovate.

---

## home.arpa names fail

**Symptoms:** `google.com` works, but `hq.home.arpa` does not.

**Checks:**

```bash
dig @192.168.1.174 hq.home.arpa +short
curl -fsS --resolve hq.home.arpa:80:192.168.1.174 http://hq.home.arpa >/dev/null
```

**Ideas:**

1. AdGuard rewrite missing/wrong (runtime config).
2. Client not using AdGuard (public DNS will not know `home.arpa` the same way).
3. NPM down (name resolves but HTTP fails) — see next sections.

---

## NPM is down

**Symptoms:** Direct `IP:port` works; friendly names fail; Homarr/HA via hostname fail.

**Checks:**

```bash
~/rowdyroost/scripts/healthcheck-stack.sh proxy-stack
docker ps --filter name=nginx-proxy-manager
curl -fsS --resolve npm.home.arpa:80:192.168.1.174 http://npm.home.arpa >/dev/null
```

**Ideas:**

1. Container stopped/crashed — `docker logs nginx-proxy-manager`
2. Ports 80/443 bound by something else on Blackblade
3. Corrupt NPM data — restore via `rollback-stack.sh proxy-stack <id>` after backup review

---

## Home Assistant is inaccessible

**Split the paths:**

| Path | Test |
|------|------|
| LAN via NPM | `curl --resolve hq.home.arpa:80:192.168.1.174 http://hq.home.arpa` |
| Direct | `http://192.168.1.174:8123` (from LAN) |
| Remote | `https://hq.therowdyroost.com` |

**Checks:**

```bash
~/rowdyroost/scripts/healthcheck-stack.sh infra-stack
docker ps --filter name=homeassistant
docker ps --filter name=cloudflared
```

**Ideas:**

- LAN NPM path fails, direct works → NPM / DNS
- Direct fails → `homeassistant` container / config
- Only remote fails → `cloudflared`, `${CLOUDFLARED_TOKEN}`, Cloudflare dashboard (outside repo)

---

## Plex is inaccessible

**Split LAN direct vs proxied:**

```bash
# On Mac
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:32400/web
~/rowdyroost/scripts/healthcheck-stack.sh plex-stack

# Via NPM (from a checker that can reach Blackblade)
curl -sS -o /dev/null -w '%{http_code}\n' \
  --resolve plex.home.arpa:80:192.168.1.174 \
  http://plex.home.arpa
```

**Ideas:**

1. `plex` container not running on Mac
2. NPM proxy target wrong (runtime) while local `:32400` works
3. DNS pointing at Blackblade but NPM cannot reach Mac — LAN routing/firewall (**needs clarification** for exact proxy upstream)

---

## qBittorrent works but downloads fail

**Meaning:** Web UI on `:8080` responds, torrents stall or error.

**Checks:**

```bash
~/rowdyroost/scripts/healthcheck-stack.sh plex-stack
docker inspect vpn --format '{{.State.Health.Status}}'
docker exec vpn wget -qO- https://ipinfo.io/ip
```

**Ideas:**

1. VPN unhealthy / no egress — fix Gluetun first (`${WIREGUARD_PRIVATE_KEY}`, Surfshark account, country endpoint)
2. Disk full under `/Users/costagalazios/media`
3. Permissions (`PUID=501`, `PGID=20`)
4. Tracker/indexer issues (app-level), not Compose

---

## VPN is unhealthy

**Checks:**

```bash
docker inspect vpn --format '{{.State.Health.Status}} {{.State.Status}}'
curl -fsS http://127.0.0.1:9999 >/dev/null
docker logs vpn | tail -100
```

**Ideas:**

1. Invalid or rotated `${WIREGUARD_PRIVATE_KEY}` in `~/docker/plex-stack/.env`
2. Provider outage / country endpoint issue (`SERVER_COUNTRIES=Mexico`)
3. Missing `NET_ADMIN` / Docker Desktop VPN quirks on Mac
4. After fix, confirm qBittorrent still `network_mode: container:vpn`

---

## Radarr/Sonarr cannot import

**Symptoms:** Download completes in qBittorrent; *arr leaves it in queue with import errors.

**Ideas:**

1. Path mismatch — both must use the shared `/media` mount consistently
2. Permissions on host files
3. Incomplete download / wrong category
4. Hardlink failed across filesystems → copy or error (see below)

Check logs inside the apps and:

```bash
docker logs radarr | tail -50
docker logs sonarr | tail -50
```

---

## Disk usage unexpectedly doubles

**Likely:** imports **copying** instead of **hardlinking**. See [MEDIA-PIPELINE.md](MEDIA-PIPELINE.md).

**Checks:**

1. Are download and library directories on the same filesystem volume?
2. Do Radarr/Sonarr remote path maps match qBittorrent’s `/media/...` paths?
3. Compare inode numbers on host (same inode ⇒ hardlink):

```bash
ls -li /Users/costagalazios/media/downloads/... 
ls -li /Users/costagalazios/media/movies/...
```

---

## A deployment fails

**Symptoms:** `deploy-stack.sh` aborts or triggers automatic rollback.

**Read the phase:**

| Message | Meaning |
|---------|---------|
| Pre-deploy health failed | Fix production before deploying |
| Could not determine pre-deployment backup | Backup step failed |
| Compose validation failed | Bad YAML or missing `.env` for infra/plex |
| Post-deploy health failed | Automatic rollback started |

**Actions:**

```bash
~/rowdyroost/scripts/healthcheck-stack.sh <stack>
ls ~/docker-backups/<stack> | tail
docker compose -f ~/docker/<stack>/docker-compose.y*ml ps
```

Do not keep force-deploying on a red baseline.

---

## A rollback fails

**Symptoms:** `ROLLBACK COMPLETED BUT HEALTH CHECK FAILED` or rollback aborts early.

**Ideas:**

1. Backup incomplete / wrong id
2. Image pull failed (network/registry)
3. Data restored but incompatible with image (migration problem)
4. For dns/infra/proxy: sudo/permissions issues on restore

**Actions:**

```bash
ls -la ~/docker-backups/<stack>/<backup-id>
~/rowdyroost/scripts/healthcheck-stack.sh <stack>
docker compose -f ~/docker/<stack>/docker-compose.y*ml logs --tail=100
```

Escalate carefully: restore an older known-good backup id, or repair data manually. Avoid mixing Compose from Git with appdata from an unrelated week without understanding migrations.

---

## Quick reference: script entry points

| Goal | Command |
|------|---------|
| Diagnose | `~/rowdyroost/scripts/healthcheck-stack.sh <stack>` |
| Snapshot | `~/rowdyroost/scripts/backup-stack.sh <stack>` |
| Apply Git Compose | `~/rowdyroost/scripts/deploy-stack.sh <stack>` |
| Restore | `~/rowdyroost/scripts/rollback-stack.sh <stack> <id>` |
