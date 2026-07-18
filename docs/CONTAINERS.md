# Containers

Every service defined in this repository’s Compose files. Service names and `container_name` values match Compose exactly.

Related: [ARCHITECTURE.md](ARCHITECTURE.md) · [MEDIA-PIPELINE.md](MEDIA-PIPELINE.md) · [NETWORKING.md](NETWORKING.md) · [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Quick index

| Container | Host | Stack | Published / notable ports |
|-----------|------|-------|---------------------------|
| `adguardhome` | Blackblade | dns-stack | Host network; health uses DNS `:53` and UI `:8002` |
| `nginx-proxy-manager` | Blackblade | proxy-stack | `80`, `81`, `443` |
| `homeassistant` | Blackblade | infra-stack | `8123` |
| `homarr` | Blackblade | infra-stack | `7575` |
| `uptime-kuma` | Blackblade | infra-stack | `3001` |
| `cloudflared` | Blackblade | infra-stack | (no host ports in Compose) |
| `vpn` (service `gluetun`) | Mac | plex-stack | `8080`, `9999` |
| `qbittorrent` | Mac | plex-stack | Via Gluetun (`8080`) |
| `plex` | Mac | plex-stack | `32400` |
| `radarr` | Mac | plex-stack | `7878` |
| `sonarr` | Mac | plex-stack | `8989` |
| `prowlarr` | Mac | plex-stack | `9696` |
| `flaresolverr` | Mac | plex-stack | `8191` |

---

## AdGuard Home

| | |
|--|--|
| **Compose service** | `adguardhome` |
| **Container name** | `adguardhome` |
| **Image** | `adguard/adguardhome:v0.107.78@sha256:…` |
| **Host** | Blackblade |
| **Stack** | `dns-stack` |

**What it does.** LAN DNS server with filtering and local rewrites (including `home.arpa` names).

**Why it exists.** Devices need a single place to resolve internet names and internal friendly names without editing every device’s hosts file.

**Important ports.** `network_mode: host` — AdGuard binds directly on the host. Health checks use:

- TCP DNS on `192.168.1.174:53`
- Web UI `http://192.168.1.174:8002`

> Port `8002` is not declared in Compose (host networking). It is the production UI port asserted by `healthcheck-stack.sh`.

**Important mounts.**

- `./adguard/work` → `/opt/adguardhome/work`
- `./adguard/conf` → `/opt/adguardhome/conf`

**Dependencies.** LAN gateway/DHCP should point clients at this DNS (DHCP config is **outside this repo** — needs clarification if documented elsewhere).

**If it stopped.** Most devices cannot resolve names; `home.arpa` breaks; anything that depends on AdGuard DNS fails. NPM hostnames stop resolving even if NPM itself is up.

**Verify health.**

```bash
~/rowdyroost/scripts/healthcheck-stack.sh dns-stack
# or: dig @192.168.1.174 example.com +short
```

**Interactions.** Feeds all clients and Uptime Kuma’s first DNS server (`192.168.1.174`). Rewrites send `*.home.arpa` traffic toward Blackblade / NPM.

---

## Nginx Proxy Manager

| | |
|--|--|
| **Compose service** | `nginx-proxy-manager` |
| **Container name** | `nginx-proxy-manager` |
| **Image** | `jc21/nginx-proxy-manager:2.15.1@sha256:…` |
| **Host** | Blackblade |
| **Stack** | `proxy-stack` |

**What it does.** Reverse proxy: terminates HTTP/HTTPS and routes by hostname to backends.

**Why it exists.** One entry point for `hq.home.arpa`, `npm.home.arpa`, `status.home.arpa`, `plex.home.arpa`, etc., instead of remembering raw IPs and ports.

**Important ports.**

- `80:80` — HTTP proxy
- `443:443` — HTTPS proxy
- `81:81` — Admin UI

**Important mounts.**

- `./data` → `/data` (proxy hosts, certificates metadata, logs)
- `./letsencrypt` → `/etc/letsencrypt`

**Dependencies.** AdGuard (or other DNS) must resolve proxy hostnames to Blackblade. Backends must be reachable from NPM’s network namespace.

**If it stopped.** Friendly `home.arpa` URLs fail even when apps are healthy. Direct `IP:port` access may still work.

**Verify health.**

```bash
~/rowdyroost/scripts/healthcheck-stack.sh proxy-stack
```

Checks NPM admin via `http://npm.home.arpa` (resolved to `192.168.1.174`) and sample proxied apps.

**Interactions.** Front door for Home Assistant, Homarr, Uptime Kuma, and proxied media UIs. Often the origin Cloudflared reaches for remote access.

---

## Home Assistant

| | |
|--|--|
| **Compose service** | `homeassistant` |
| **Container name** | `homeassistant` |
| **Image** | `ghcr.io/home-assistant/home-assistant:2026.7.2@sha256:…` |
| **Host** | Blackblade |
| **Stack** | `infra-stack` |

**What it does.** Home automation hub and dashboard.

**Why it exists.** Control and observe the home (automations, devices, dashboards).

**Important ports.** `8123:8123`

**Important mounts.** `./homeassistant/config` → `/config`

**Environment.** `TZ=America/Chicago`. Runs `privileged: true` (required for some device integrations — treat as high trust).

**Dependencies.** Prefer access via NPM (`hq.home.arpa`). Remote check: `https://hq.therowdyroost.com` (Cloudflared).

**If it stopped.** Automations and the HQ dashboard stop; remote `hq.therowdyroost.com` fails health checks.

**Verify health.**

```bash
~/rowdyroost/scripts/healthcheck-stack.sh infra-stack
```

**Interactions.** Cloudflared (remote), NPM (LAN name), Homarr/Uptime Kuma may link to it.

---

## Homarr

| | |
|--|--|
| **Compose service** | `homarr` |
| **Container name** | `homarr` |
| **Image** | `ghcr.io/homarr-labs/homarr:latest@sha256:…` (digest-pinned; Renovate disables auto version bumps while on `latest`) |
| **Host** | Blackblade |
| **Stack** | `infra-stack` |

**What it does.** Homelab dashboard / start page for links to other services.

**Why it exists.** Single “front door” UI for humans navigating the lab.

**Important ports.** `7575:7575`

**Important mounts.**

- `./homarr/appdata` → `/appdata`
- `/var/run/docker.sock` → `/var/run/docker.sock:ro` (read-only Docker visibility)

**Secrets.** `${HOMARR_SECRET_ENCRYPTION_KEY}` from live `.env`.

**Dependencies.** NPM hostname `homarr.home.arpa` (health check). Docker socket for container widgets.

**If it stopped.** Dashboard unavailable; other services keep running.

**Verify health.** Container up + `http://homarr.home.arpa` via NPM (infra healthcheck).

**Interactions.** Discovers/links other containers; does not replace NPM or DNS.

---

## Uptime Kuma

| | |
|--|--|
| **Compose service** | `uptime-kuma` |
| **Container name** | `uptime-kuma` |
| **Image** | `louislam/uptime-kuma:1.23.17@sha256:…` |
| **Host** | Blackblade |
| **Stack** | `infra-stack` |

**What it does.** Status monitoring and uptime history for URLs/services you configure in its UI.

**Why it exists.** Early warning when DNS, proxies, or apps break.

**Important ports.** `3001:3001`

**Important mounts.**

- `./uptime-kuma/data` → `/app/data`
- `/var/run/docker.sock` → `/var/run/docker.sock:ro`

**DNS inside container.** `192.168.1.174` then `1.1.1.1` — prefers AdGuard, falls back to Cloudflare DNS.

**Dependencies.** AdGuard preferred for resolving monitored `home.arpa` targets.

**If it stopped.** You lose monitoring/alerting UI; monitored apps keep running.

**Verify health.** Container up + `http://status.home.arpa` via NPM.

**Interactions.** Monitors other services; does not proxy traffic.

---

## Cloudflared

| | |
|--|--|
| **Compose service** | `cloudflared` |
| **Container name** | `cloudflared` |
| **Image** | `cloudflare/cloudflared:2026.7.2@sha256:…` |
| **Host** | Blackblade |
| **Stack** | `infra-stack` |

**What it does.** Runs a Cloudflare Tunnel (`tunnel --no-autoupdate --protocol http2 run --token ${CLOUDFLARED_TOKEN}`).

**Why it exists.** Expose selected services (at least Home Assistant at `hq.therowdyroost.com`) without opening inbound router ports.

**Important ports.** None published in Compose; outbound to Cloudflare.

**Important mounts.** None in Compose.

**Secrets.** `${CLOUDFLARED_TOKEN}` from live `.env`.

**Dependencies.** Working internet; valid tunnel token; origin service healthy.

**If it stopped.** LAN access via `home.arpa` may still work; **remote** `https://hq.therowdyroost.com` fails (infra healthcheck covers this).

**Verify health.** Container running + external HTTPS check in `healthcheck-stack.sh infra-stack`.

**Interactions.** Cloudflare edge ↔ local origin (often NPM / Home Assistant). Exact ingress map is **not in this repo**.

---

## Gluetun (`vpn`)

| | |
|--|--|
| **Compose service** | `gluetun` |
| **Container name** | `vpn` |
| **Image** | `qmcgaw/gluetun@sha256:…` (digest-only pin in Compose) |
| **Host** | Mac |
| **Stack** | `plex-stack` |

**What it does.** VPN client (Surfshark WireGuard) that other containers can share as their network stack.

**Why it exists.** Send BitTorrent traffic through a VPN with a kill-switch-style enclosure (qBittorrent has no separate network path).

**Important ports (published on Gluetun).**

- `8080:8080` — qBittorrent Web UI (because qBittorrent shares this network namespace)
- `9999:9999` — Gluetun health endpoint (`HEALTH_SERVER_ADDRESS=0.0.0.0:9999`)

**Important mounts.** `/Users/costagalazios/docker/appdata/gluetun` → `/gluetun`

**Key environment (non-secret).** `VPN_SERVICE_PROVIDER=surfshark`, `VPN_TYPE=wireguard`, `WIREGUARD_ADDRESSES=10.14.0.2/16`, `SERVER_COUNTRIES=Mexico`, `FIREWALL_OUTBOUND_SUBNETS=192.168.0.0/16,10.0.0.0/8`, `DOT=off`, `DNS_ADDRESS=9.9.9.9`, `cap_add: NET_ADMIN`.

**Secrets.** `${WIREGUARD_PRIVATE_KEY}`

**Dependencies.** Valid WireGuard credentials; host kernel support for VPN (`NET_ADMIN`).

**If it stopped.** qBittorrent loses networking (shared netns). Downloads stop. Other plex-stack apps that do not share the VPN keep working.

**Verify health.**

```bash
~/rowdyroost/scripts/healthcheck-stack.sh plex-stack
# Docker health = healthy; http://127.0.0.1:9999; VPN egress via docker exec vpn wget ...
```

**Interactions.** Owns the network for `qbittorrent`. See [MEDIA-PIPELINE.md](MEDIA-PIPELINE.md).

---

## qBittorrent

| | |
|--|--|
| **Compose service** | `qbittorrent` |
| **Container name** | `qbittorrent` |
| **Image** | `lscr.io/linuxserver/qbittorrent:latest@sha256:…` |
| **Host** | Mac |
| **Stack** | `plex-stack` |

**What it does.** BitTorrent client used by Radarr/Sonarr as a download client.

**Why it exists.** Fetch torrents that the *arr apps request.

**Important ports.** None of its own — `network_mode: container:vpn`. UI via Gluetun’s published `8080` (`WEBUI_PORT=8080`).

**Important mounts.**

- `/Users/costagalazios/docker/appdata/qbittorrent` → `/config`
- `/Users/costagalazios/media` → `/media`

**Dependencies.** `depends_on: gluetun`; healthy VPN; shared `/media` with Radarr/Sonarr for hardlink imports.

**If it stopped.** New downloads fail; completed files already on disk remain; *arr apps cannot grab new torrents.

**Verify health.** Container running + reachable `http://127.0.0.1:8080` (auth response OK).

**Interactions.** Controlled by Radarr/Sonarr; traffic via Gluetun; writes under `/media`.

---

## Plex

| | |
|--|--|
| **Compose service** | `plex` |
| **Container name** | `plex` |
| **Image** | `lscr.io/linuxserver/plex:latest@sha256:…` |
| **Host** | Mac |
| **Stack** | `plex-stack` |

**What it does.** Media server for movies/TV libraries.

**Why it exists.** Playback for family devices.

**Important ports.** `32400:32400`

**Important mounts.**

- `/Users/costagalazios/docker/appdata/plex` → `/config`
- `/Users/costagalazios/media` → `/media`

**Dependencies.** Library files under `/media`; optional NPM name `plex.home.arpa` (proxy health on Blackblade).

**If it stopped.** Playback fails; downloads/imports can continue.

**Verify health.** `http://127.0.0.1:32400/web` reachable (1xx–4xx OK without token).

**Interactions.** Reads libraries populated by Radarr/Sonarr imports; may be reverse-proxied through NPM.

---

## Radarr

| | |
|--|--|
| **Compose service** | `radarr` |
| **Container name** | `radarr` |
| **Image** | `lscr.io/linuxserver/radarr:latest@sha256:…` |
| **Host** | Mac |
| **Stack** | `plex-stack` |

**What it does.** Movie collection manager: search, send to download client, import into library.

**Why it exists.** Automate movie acquisition and library organization.

**Important ports.** `7878:7878`

**Important mounts.**

- `/Users/costagalazios/docker/appdata/radarr` → `/config`
- `/Users/costagalazios/media` → `/media`

**Dependencies.** Prowlarr (indexers), qBittorrent (downloads), shared `/media` paths for hardlinks. FlareSolverr may be used by indexers that need it (configured in apps, not Compose).

**If it stopped.** Movie automation stops; existing files and Plex remain.

**Verify health.** `http://127.0.0.1:7878` reachable.

**Interactions.** Prowlarr → Radarr → qBittorrent → `/media` → Plex. See [MEDIA-PIPELINE.md](MEDIA-PIPELINE.md).

---

## Sonarr

| | |
|--|--|
| **Compose service** | `sonarr` |
| **Container name** | `sonarr` |
| **Image** | `lscr.io/linuxserver/sonarr:latest@sha256:…` |
| **Host** | Mac |
| **Stack** | `plex-stack` |

**What it does.** Same role as Radarr, for TV series.

**Important ports.** `8989:8989`

**Important mounts.**

- `/Users/costagalazios/docker/appdata/sonarr` → `/config`
- `/Users/costagalazios/media` → `/media`

**Dependencies.** Same pattern as Radarr.

**If it stopped.** TV automation stops; other services continue.

**Verify health.** `http://127.0.0.1:8989` reachable.

**Interactions.** Parallel to Radarr in the media pipeline.

---

## Prowlarr

| | |
|--|--|
| **Compose service** | `prowlarr` |
| **Container name** | `prowlarr` |
| **Image** | `lscr.io/linuxserver/prowlarr:latest@sha256:…` |
| **Host** | Mac |
| **Stack** | `plex-stack` |

**What it does.** Indexer manager: configures torrent/Usenet indexers once and syncs them to Radarr/Sonarr.

**Why it exists.** Avoid duplicating indexer settings in every *arr app.

**Important ports.** `9696:9696`

**Important mounts.** `/Users/costagalazios/docker/appdata/prowlarr` → `/config` only (no `/media` mount in Compose).

**Dependencies.** Network to indexers; often FlareSolverr for challenged sites (app-level config).

**If it stopped.** Radarr/Sonarr may keep using last-synced indexers for a while, but indexer management/sync breaks — **needs clarification** how apps behave offline from Prowlarr in your exact versions.

**Verify health.** `http://127.0.0.1:9696` reachable.

**Interactions.** Upstream of Radarr/Sonarr search.

---

## FlareSolverr

| | |
|--|--|
| **Compose service** | `flaresolverr` |
| **Container name** | `flaresolverr` |
| **Image** | `ghcr.io/flaresolverr/flaresolverr:latest@sha256:…` |
| **Host** | Mac |
| **Stack** | `plex-stack` |

**What it does.** Proxy that solves Cloudflare-style browser challenges so indexers can be scraped.

**Why it exists.** Some indexers block simple HTTP clients; Prowlarr/other apps can route those through FlareSolverr.

**Important ports.** `8191:8191`

**Important mounts.** None in Compose (stateless).

**Dependencies.** Used when configured in Prowlarr (or related apps); not wired in Compose beyond being on the same host.

**If it stopped.** Indexers that require challenge solving fail; others may still work.

**Verify health.** `http://127.0.0.1:8191` reachable.

**Interactions.** Helper for Prowlarr/indexers — not on the download data path.

---

## Backup coverage note

`backup-stack.sh` for `plex-stack` copies appdata for `gluetun`, `qbittorrent`, `plex`, `radarr`, `sonarr`, `prowlarr`. It does **not** back up FlareSolverr (no persistent data) and does **not** back up `/Users/costagalazios/media`. See [BACKUP-AND-RECOVERY.md](BACKUP-AND-RECOVERY.md).
