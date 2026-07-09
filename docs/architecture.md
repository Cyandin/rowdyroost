# Architecture

## Network Flow

    Internet
        │
        ▼
 Cloudflare Tunnel
        │
        ▼
 Nginx Proxy Manager
        │
        ▼
    AdGuard Home (DNS)
        │
        ▼
      home.arpa
        │
        ├── hq.home.arpa          → Home Assistant
        ├── npm.home.arpa         → Nginx Proxy Manager
        ├── adguard.home.arpa     → AdGuard Home
        ├── status.home.arpa      → Uptime Kuma
        ├── plex.home.arpa        → Plex
        ├── radarr.home.arpa      → Radarr
        ├── sonarr.home.arpa      → Sonarr
        ├── prowlarr.home.arpa    → Prowlarr
        ├── qbittorrent.home.arpa → qBittorrent
        └── website.home.arpa     → Website

## Physical Network

- Gateway: 192.168.1.1
- Server: 192.168.1.36
- LAN: 192.168.1.0/24
- Domain: home.arpa

## Docker Stacks

- dns-stack
  - AdGuard Home

- infra-stack
  - Home Assistant
  - Clouowlarr
  - qBittorrent
  - Gluetun VPN
  - FlareSolverr

## Monitoring

- Uptime Kuma
- Home Assistant
