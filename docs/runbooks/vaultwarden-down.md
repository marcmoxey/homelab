# Runbook: ServiceDown — Vaultwarden

| | |
|---|---|
| **Alert** | `ServiceDown{service="vaultwarden"}` (severity: **critical**) |
| **Rule** | `probe_success == 0` for 2m — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | The Beelink can't load `https://nas.tailf2e508.ts.net/alive` with a 2xx answer for 2 minutes |
| **Impact** | Bitwarden apps keep working **read-only** from their offline copy: you can still look up passwords. You **can't** save new or changed passwords, sync between devices, or log in on a new device |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy `homelab-alerts` → phone |
| **Expected detection time** | ~3 min (15s scrape + 2m `for` + 30s `group_wait`) |
| **Does NOT cover** | The blackbox exporter being down (**TargetDown**, job `blackbox`); the whole NAS down (**TargetDown** for its exporters fires too); the certificate getting close to expiring (**CertExpiringSoon**); a missed nightly backup (healthchecks.io) |

## How the check works

The blackbox exporter on the Beelink loads Vaultwarden's built-in health page, `/alive`, through the **same HTTPS address the apps use**. So one probe covers the container, `tailscale serve`, the Tailscale certificate and the network between the two machines.

| Piece | Where | Details |
|---|---|---|
| Vaultwarden | NAS, `nas/vaultwarden/compose.yml` | Container `vaultwarden`, listens on `127.0.0.1:8080` only |
| HTTPS | NAS, `tailscale serve` | `https://nas.tailf2e508.ts.net` → `http://127.0.0.1:8080`, tailnet only. No UFW rule (nothing listens on the LAN) |
| Data | NAS NVMe, `/opt/appdata/vaultwarden` | `db.sqlite3` (the vault), `attachments/`, `sends/`, `rsa_key*` (signs logins), `config.json` |
| Backups | NAS, `nas/vaultwarden/backup.sh`, root cron 03:45 (Ansible) | `/tank/backups/vaultwarden/<date>/` |
| Emergency sheet | Paper, offline | Master password, 2FA recovery code, Tailscale/GitHub logins |
| Probe | Beelink, `prometheus.yml` job `blackbox-http` | Label `service: vaultwarden` |

**Note:** the vault data is encrypted with your master password on your devices before it's ever sent. A stolen backup can't be read without that password, but losing the master password means losing the vault; the server can't reset it.

---

## 1. Confirm (1 min)

From the Beelink — what does the probe see?

```bash
docker exec prometheus wget -qO- "http://blackbox:9115/probe?target=https://nas.tailf2e508.ts.net/alive&module=http_2xx&debug=true" | head -40
```

On the NAS, test each layer from the inside out:

```bash
ssh nas
cd /opt/stacks/nas/vaultwarden
docker compose ps                          # running + (healthy)?
curl -I http://127.0.0.1:8080/alive        # the container itself
tailscale serve status                     # is the HTTPS proxy still set up?
curl -I https://nas.tailf2e508.ts.net/alive   # the full path the apps use
```

## 2. Diagnose

```bash
docker compose logs --tail=50 vaultwarden
df -h /opt/appdata
tailscale status | head
```

| What you see | Usually means |
|---|---|
| Container not running / restarting | Crashed or bad config — read its logs |
| `127.0.0.1:8080` works, `tailscale serve status` is empty | The serve config is gone (e.g. after a Tailscale reset or re-login) |
| `127.0.0.1:8080` works, HTTPS gives a certificate error | Tailscale cert problem — HTTPS disabled in the admin console, or renewal failed |
| Everything works on the NAS, the probe fails | Tailscale between the Beelink and the NAS, or the blackbox container can't resolve `*.ts.net` (DNS) |
| Logs: `database is locked` / `disk I/O error` / `No space left` | NVMe full or the database file is damaged |
| Logs: `rsa_key` errors | The signing key files are missing or unreadable |

## 3. Fix

| Cause | Fix |
|---|---|
| Container stopped/crashed | `docker compose up -d` (in `nas/vaultwarden`) |
| `tailscale serve` missing | `sudo tailscale serve --bg 8080`, then `tailscale serve status` |
| Certificate error | Tailscale admin console → **DNS** → check **MagicDNS** and **HTTPS Certificates** are on; `sudo tailscale cert nas.tailf2e508.ts.net` to force a fetch |
| Blackbox can't resolve `*.ts.net` | On the Beelink, add `dns: [100.100.100.100]` to the `blackbox` service, `docker compose up -d blackbox` |
| Disk full | Free space on `/opt/appdata` (old logs, unused images: `docker image prune`) |
| Database damaged | **Restore from backup** (below) |

### Restore from backup

1. Pick a backup: `ls -1 /tank/backups/vaultwarden/`
2. Stop Vaultwarden: `docker compose stop vaultwarden`
3. Keep the broken data in case you need it: `sudo mv /opt/appdata/vaultwarden /opt/appdata/vaultwarden.broken-$(date +%F)`
4. Put the backup in place:
   ```bash
   B=/tank/backups/vaultwarden/<chosen-date>
   sudo mkdir -p /opt/appdata/vaultwarden
   sudo tar -xzf "$B/vaultwarden.tar.gz" -C /opt/appdata/vaultwarden
   ```
5. Start it: `docker compose up -d`, log in on the web vault, check a recent item and an attachment.
6. On each device: Bitwarden app → **Sync now**.

Anything saved after that backup was taken is only on the devices that saved it — check those devices still have it and re-save if needed.

**Don't:** set `SIGNUPS_ALLOWED` back to true to "get back in"; delete `rsa_key*` (everyone gets logged out, and it can break logins); publish port 8080 on `0.0.0.0` or port-forward it; enable the `/admin` page as a quick fix; keep your only copy of the master password or 2FA recovery code inside the vault.

## 4. Verify (the incident isn't over until all are true)

- [ ] `docker compose ps` → `vaultwarden` running **(healthy)**
- [ ] `curl -I https://nas.tailf2e508.ts.net/alive` → `200` from the NAS **and** from the Beelink
- [ ] Web vault login works; a phone app **Sync now** succeeds
- [ ] Save a test item on one device, see it on another, then delete it
- [ ] Prometheus → Alerts → `ServiceDown` for vaultwarden **Inactive**
- [ ] **`[RESOLVED] ServiceDown` (vaultwarden) arrived on the phone**

## 5. Follow up

- [ ] Real outage? Postmortem in `docs/postmortems/YYYY-MM-DD-<name>.md`
- [ ] Restored from backup? Note how much was lost (time since the last backup)
- [ ] Emergency sheet still up to date? (master password, 2FA recovery code)
- [ ] Row in the History table below + the brag doc's Incidents table
- [ ] Step missing or wrong? Fix this runbook and commit

## History

| Date | What happened | Detect | Down for | Postmortem |
|---|---|---|---|---|
| 2026-11-19 | Drill: stopped container to test ServiceDown (critical) | FIRING 6:04 PM | ~5 min (RESOLVED 6:09 PM) | — |
