# Scripts

Four production scripts under `scripts/`. They are the operational API for this homelab — prefer them over ad-hoc `docker compose` when changing production.

Related: [DEPLOYMENTS.md](DEPLOYMENTS.md) · [BACKUP-AND-RECOVERY.md](BACKUP-AND-RECOVERY.md) · [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Shared assumptions

| Variable | Value |
|----------|--------|
| Repo | `$HOME/rowdyroost` |
| Live stacks | `$HOME/docker/<stack>` |
| Backups | `$HOME/docker-backups/<stack>/<timestamp>` |

All scripts use `bash` with `set -Eeuo pipefail` (fail fast on errors/unset vars).

Allowed stacks: `dns-stack` | `infra-stack` | `proxy-stack` | `plex-stack`.

Compose filename: `docker-compose.yml` for `plex-stack`, `docker-compose.yaml` for the others.

---

## `backup-stack.sh`

### Purpose

Create a timestamped, permission-locked snapshot of a live stack’s Compose file, image evidence, and application data **before** risky changes.

### Inputs

```bash
./scripts/backup-stack.sh <stack>
```

### Workflow

1. Validate stack name; require `$HOME/docker/<stack>` exists.
2. Create `$HOME/docker-backups/<stack>/<timestamp>/`.
3. For non–plex-stack: verify `sudo` (`sudo -v`).
4. Record `docker compose config`, images, `ps`, inspect digests.
5. Copy stack-specific files (see [BACKUP-AND-RECOVERY.md](BACKUP-AND-RECOVERY.md)).
6. `chmod -R go-rwx` on the backup (and chown for Linux stacks).

### Safety controls

- Refuses unknown stack names.
- Does not modify running containers.
- Restricts backup permissions so group/other cannot read secrets.

### Failure behavior

Exits non-zero if the live stack directory is missing or a copy fails (`set -e`). Partial directories may exist — inspect before relying on them.

### Example

```bash
~/rowdyroost/scripts/backup-stack.sh proxy-stack
```

---

## `healthcheck-stack.sh`

### Purpose

Prove a stack is healthy enough for production using the same checks deploys gate on. Retries (`RETRIES=6`, `RETRY_DELAY=5`) absorb slow starts.

### Inputs

```bash
./scripts/healthcheck-stack.sh <stack>
```

### Workflow (by stack)

| Stack | Checks (summary) |
|-------|------------------|
| dns-stack | Container `adguardhome`; TCP `:53` on `192.168.1.174`; `dig @192.168.1.174`; UI `:8002` |
| infra-stack | Containers HA/Homarr/Uptime/Cloudflared; NPM hostnames for hq/homarr/status; external `https://hq.therowdyroost.com` |
| proxy-stack | NPM container; `npm.home.arpa`; sample `hq.home.arpa`; reachable `plex.home.arpa` |
| plex-stack | VPN healthy; all media containers; VPN egress IP; Gluetun `:9999`; local UIs on 8080/32400/7878/8989/9696/8191 |

Helpers distinguish strict HTTP success (`curl -fsS`) vs “reachable” (`HTTP 1xx–4xx`) for apps that demand auth.

### Safety controls

- Read-only regarding stack data (aside from normal HTTP/DNS probes).
- Exit code `1` if any check fails — suitable for automation gates.

### Failure behavior

Prints `PASS` / `FAIL` counts; non-zero exit on any failure. Does not roll back by itself.

### Example

```bash
~/rowdyroost/scripts/healthcheck-stack.sh plex-stack
```

---

## `deploy-stack.sh`

### Purpose

Apply the **Git-approved** Compose file to the live stack with backup + verify + automatic rollback.

### Inputs

```bash
./scripts/deploy-stack.sh <stack>
```

### Workflow

1. Pre-deploy `healthcheck-stack.sh` — **abort** if already unhealthy.
2. `backup-stack.sh`; resolve latest backup id.
3. `docker compose config` against repo Compose (with live `.env` for infra/plex when required).
4. `cp` Compose from `$HOME/rowdyroost/<stack>/` → `$HOME/docker/<stack>/`.
5. `docker compose pull` && `up -d` in the live directory.
6. Post healthcheck — success prints backup id; failure calls `rollback-stack.sh <stack> <id> --automatic`.

### Safety controls

- Will not deploy over a red baseline.
- Always backups first.
- Validates Compose before copying.
- Automatic rollback on failed verification.

### Failure behavior

- Precheck fail → exit 1, no changes.
- Backup/config/pull/up errors → script aborts via `set -e` (may leave partial state; investigate).
- Postcheck fail → automatic rollback attempted.

### Example

```bash
cd ~/rowdyroost && git pull
~/rowdyroost/scripts/deploy-stack.sh infra-stack
```

### Design intent

Humans approve bits in GitHub; this script makes “merged on main” become “running locally” without skipping evidence or undo.

---

## `rollback-stack.sh`

### Purpose

Restore a previous backup’s Compose + appdata, recreate containers, and re-run health checks.

### Inputs

```bash
./scripts/rollback-stack.sh <stack> [backup-id|latest] [manual|--automatic]
```

Defaults: `backup-id=latest`, mode=`manual`.

### Workflow

1. Resolve backup directory under `$HOME/docker-backups/<stack>/`.
2. Manual mode: require typing `ROLLBACK`.
3. `docker compose down` in live stack.
4. Replace appdata + Compose from backup (stack-specific).
5. `docker compose pull && up -d`.
6. Run healthcheck; report success or “completed but health check failed.”

### Safety controls

- Confirmation phrase in manual mode.
- Automatic mode only when explicitly passed (deploy uses this).
- `sudo` for Linux stack file ownership where needed.

### Failure behavior

- Missing backup / Compose in backup → exit 1 before destructive restore.
- Health fail after restore → exit 1 (stack may be up but unhealthy).

### Example

```bash
~/rowdyroost/scripts/rollback-stack.sh dns-stack 20260717-181015
```

### Design intent

Rollback restores a **known pair** of config + data from one timestamp, not “whatever image latest happens to be” alone — then re-pulls the images referenced by that restored Compose.
