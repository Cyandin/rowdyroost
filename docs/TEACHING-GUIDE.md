# Teaching guide

A progressive path for a parent teaching a teenager how this homelab works. Each lesson uses **this repository** as the lab bench.

Related: [GLOSSARY.md](GLOSSARY.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

**Ground rules for both of you**

- Prefer read-only commands until Lesson 12.
- Never paste secrets from `.env` into chat, school docs, or Git.
- Run stack scripts only on the host that owns that stack (Blackblade vs Mac).

---

## Lesson 1: What is a server?

A **server** is a computer whose job is to answer requests for other devices.

In this lab:

- **Blackblade** answers DNS and hosts Home Assistant, the reverse proxy, and monitoring.
- The **Mac** answers Plex playback and runs the download automation stack.

**Try:** From a phone on Wi‑Fi, open `http://hq.home.arpa` (if DNS works). That phone is a *client*; Blackblade is serving the page (via NPM → Home Assistant).

**Discuss:** How is a server different from “the computer you sit in front of”? (Same machine can be both — the Mac is.)

---

## Lesson 2: What is Linux?

Many servers run **Linux** (or Linux-like environments inside Docker). Containers in this repo are almost all Linux images even when the Mac host is macOS.

You do not need to install Linux on a laptop to learn: `docker exec` drops you into a Linux userspace inside a container.

**Try (on the Mac, read-only):**

```bash
docker exec plex uname -a
```

**Discuss:** Why pin `TZ=America/Chicago` in Compose? (Clocks, logs, schedules.)

---

## Lesson 3: What is Docker?

**Docker** runs applications in isolated **containers** so each app has its own files and processes without a full separate virtual machine for every service.

This repo’s unit of deployment is a **Compose stack** (`dns-stack`, `proxy-stack`, `infra-stack`, `plex-stack`).

**Try:**

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

**Discuss:** Why group AdGuard alone in `dns-stack`? (Blast radius — DNS is sacred.)

---

## Lesson 4: Image vs container

| Term | Analogy | Example |
|------|---------|---------|
| **Image** | Cookie cutter / class | `louislam/uptime-kuma:1.23.17@sha256:…` |
| **Container** | Cookie / object | Running `uptime-kuma` |

Images are pinned with version tags **and** digests so Monday’s pull matches Friday’s. See [DEPLOYMENTS.md](DEPLOYMENTS.md).

**Try:**

```bash
docker image inspect louislam/uptime-kuma:1.23.17 --format '{{index .RepoDigests 0}}'
```

(Only works if that image is present on the machine.)

---

## Lesson 5: Ports

A **port** is a numbered doorway on an IP address.

| Service | Port in Compose |
|---------|-----------------|
| NPM HTTP | 80 |
| NPM admin | 81 |
| Home Assistant | 8123 |
| Plex | 32400 |
| qBittorrent UI (via Gluetun) | 8080 |

**Try:** Why can two containers both use port 8080 *inside* their own network namespaces, but only one can publish host port 8080?

**Discuss:** AdGuard uses **host networking** — it does not use `ports:` in Compose the same way.

---

## Lesson 6: Volumes and persistent data

Containers are disposable; **volumes/bind mounts** keep data.

Examples:

- Home Assistant: `./homeassistant/config` → `/config`
- Plex: `/Users/costagalazios/docker/appdata/plex` → `/config`
- Shared library tree: `/Users/costagalazios/media` → `/media`

**Try:** If you removed the Plex container but kept `appdata/plex`, would the library settings come back? (Yes — that is the point.)

**Discuss:** Why media is **not** in `backup-stack.sh` for plex-stack. See [BACKUP-AND-RECOVERY.md](BACKUP-AND-RECOVERY.md).

---

## Lesson 7: DNS

**DNS** turns names into IPs. AdGuard is the LAN’s DNS brain.

**Try (from a machine that can reach Blackblade):**

```bash
dig @192.168.1.174 example.com +short
dig @192.168.1.174 hq.home.arpa +short
```

**Discuss:** If DNS is broken, NPM can be healthy and still look “down.” Order of debugging matters ([TROUBLESHOOTING.md](TROUBLESHOOTING.md)).

---

## Lesson 8: Reverse proxies

NPM reads the `Host` header (`hq.home.arpa`) and forwards to the right backend.

**Analogy:** School office — one front desk, many classrooms behind it.

**Try:** Compare opening Home Assistant via `http://hq.home.arpa` vs `http://192.168.1.174:8123` (if firewalls allow). Same app, different front door.

---

## Lesson 9: VPNs

A **VPN** encrypts and redirects traffic. Here, **only qBittorrent** is forced through Gluetun (`network_mode: container:vpn`).

**Try:**

```bash
~/rowdyroost/scripts/healthcheck-stack.sh plex-stack
```

Look for VPN egress and Gluetun `:9999`.

**Discuss:** Why Plex is *not* on the VPN (LAN performance, remote friends, different threat model). Needs family policy judgment — not a Compose law of nature.

---

## Lesson 10: Git and source control

Git stores the **approved recipe** (Compose + scripts). GitHub is where Renovate opens PRs.

**Try:**

```bash
cd ~/rowdyroost
git log --oneline -5
git status
```

**Discuss:** Why `.env` is gitignored. What would happen if `${WIREGUARD_PRIVATE_KEY}` were committed?

---

## Lesson 11: Health checks

A health check answers: “Is this stack fit for users *right now*?”

This lab’s checks are in `scripts/healthcheck-stack.sh` — container state, DNS, HTTP, VPN egress, external HA URL.

**Try:** Run a healthcheck and read each line aloud. Predict which check would fail if you stopped NPM.

---

## Lesson 12: Backups and rollback

**Backup** = copy of config + app data + evidence of which images ran.  
**Rollback** = put that copy back and start again.

**Try (supervised):**

```bash
~/rowdyroost/scripts/backup-stack.sh plex-stack
ls ~/docker-backups/plex-stack | tail
```

Do **not** run rollback casually on production without a reason.

**Discuss:** Migration risk — old database + new image. See [BACKUP-AND-RECOVERY.md](BACKUP-AND-RECOVERY.md).

---

## Lesson 13: Automated dependency management

**Renovate** watches for new images, pins digests, waits 7 days, opens PRs, never automerges Docker updates here.

**Try:** Open `renovate.json` and find: digest pinning, major disabled, Blackblade patch group, plex-stack manual review.

**Discuss:** Speed vs safety. Why majors are off.

---

## Lesson 14: Troubleshooting a real outage

Pick a safe drill (parent-supervised):

1. Note baseline: `healthcheck-stack.sh proxy-stack`
2. Stop NPM: `docker stop nginx-proxy-manager` (Blackblade only)
3. Observe what breaks (`home.arpa` sites vs direct `:8123`)
4. Restore: `docker start nginx-proxy-manager` or deploy/rollback path
5. Re-check health

Then walk [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for “NPM is down” without causing a real outage if you prefer tabletop-only.

**Capstone question:** “Nothing resolves on the Wi‑Fi.” What do you check first — Plex, or AdGuard? Why?

---

## Suggested pacing

| Week | Lessons |
|------|---------|
| 1 | 1–4 |
| 2 | 5–8 |
| 3 | 9–11 |
| 4 | 12–14 + one real incident write-up |
