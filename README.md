# Rowdy Roost HQ Infrastructure

Docker Compose infrastructure for Rowdy Roost HQ.

## Core Services

- AdGuard Home - LAN DNS, filtering, `.home.arpa` rewrites
- Nginx Proxy Manager - internal reverse proxy
- Home Assistant - automation dashboard
- Cloudflared - Cloudflare Tunnel
- Uptime Kuma - monitoring
- Plex / Radarr / Sonarr / Prowlarr / qBittorrent - media stack

## Network

- LAN: `192.168.1.0/24`
- Gateway: `192.168.1.1`
- Server: `192.168.1.36`
- Internal domain: `home.arpa`

## Notes

Secrets, tokens, runtime data, and app configs are intentionally excluded.
Use `.env.example` files as templates.
