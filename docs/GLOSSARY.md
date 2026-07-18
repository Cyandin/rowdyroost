# Glossary

Simple, accurate definitions as used in this homelab.

Related: [TEACHING-GUIDE.md](TEACHING-GUIDE.md) · [ARCHITECTURE.md](ARCHITECTURE.md)

| Term | Definition |
|------|------------|
| **AdGuard Home** | LAN DNS server with filtering and local rewrites (`adguardhome` container). |
| **Bind mount** | Host directory mapped into a container (for example `./data:/data`). |
| **Blackblade** | Infrastructure host at `192.168.1.174` running dns/proxy/infra stacks (per health checks and Renovate grouping). |
| **Cloudflared** | Cloudflare Tunnel client container that connects private origins to Cloudflare’s edge. |
| **Compose / Docker Compose** | YAML file declaring multi-container apps (`docker-compose.yaml` / `.yml`). |
| **Container** | Running instance of an image. |
| **Container name** | Stable name from `container_name` (for example `vpn` for Gluetun). |
| **Digest (SHA256)** | Content hash pinning an exact image. Written as `@sha256:…`. |
| **DNS** | System that resolves names to IP addresses. |
| **Docker** | Platform for building and running containers. |
| **FlareSolverr** | Helper that solves browser challenges for some indexers. |
| **Git** | Version control; this repo’s history of approved configs. |
| **GitHub** | Hosted Git + pull requests; Renovate opens update PRs here. |
| **Gluetun** | VPN client container (`gluetun` service, `vpn` container name). |
| **Hardlink** | Second directory entry pointing at the same file data on one filesystem. |
| **Health check** | Automated test that a service is usable; see `healthcheck-stack.sh`. |
| **home.arpa** | Special-use domain for home network names. |
| **Homarr** | Homelab dashboard UI. |
| **Home Assistant** | Home automation platform (`homeassistant`). |
| **Host networking** | Container shares the host’s network namespace (`network_mode: host`). |
| **Image** | Immutable template used to create containers. |
| **Indexer** | Site/API listing torrent or Usenet releases; managed via Prowlarr. |
| **LAN** | Local Area Network — here `192.168.1.0/24`. |
| **Mac media host** | Machine running `plex-stack` with `/Users/costagalazios/...` paths. |
| **Nginx Proxy Manager (NPM)** | Web UI for reverse proxy + certificates. |
| **Pin / pin digest** | Lock an image to a digest so pulls are reproducible. |
| **Plex** | Media server for playback. |
| **Port** | Numbered endpoint on an IP (for example `8123`). |
| **Prowlarr** | Indexer manager for the *arr ecosystem. |
| **Published port** | Host port mapped to a container port (`8080:8080`). |
| **qBittorrent** | BitTorrent client used as download client. |
| **Radarr** | Movie automation (*arr). |
| **Renovate** | Bot that proposes dependency/image updates via PRs. |
| **Reverse proxy** | Front-end HTTP router that forwards to backends by hostname. |
| **Rollback** | Restore previous Compose + data after a bad change. |
| **Secret** | Credential such as `${WIREGUARD_PRIVATE_KEY}` — never commit to Git. |
| **Semantic version** | Version like `1.23.17` or `2026.7.2` conveying compatibility intent. |
| **Service (Compose)** | Named unit under `services:` in Compose (may differ from container name). |
| **Sonarr** | TV automation (*arr). |
| **Stack** | One Compose project directory (`dns-stack`, etc.). |
| **Uptime Kuma** | Uptime monitoring UI. |
| **Volume** | Docker-managed or bind-mounted persistent storage. |
| **VPN** | Encrypted tunnel to a provider; here Surfshark via WireGuard in Gluetun. |
| **WireGuard** | Modern VPN protocol used by Gluetun in this lab. |
