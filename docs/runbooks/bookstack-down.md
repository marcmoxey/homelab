# Runbook: BookStackDown

| | |
|---|---|
| **Alert** | `BookStackDown` (severity: warning) |
| **Rule** | `probe_success{service="bookstack"} == 0` for 2m — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | The Beelink can't load BookStack's login page (`http://100.105.219.6:6875/login`) with a 2xx answer for 2 minutes |
| **Impact** | The wiki (notes, docs) is unavailable. Nothing is lost while it's down: pages live in the database on the NAS |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy `homelab-alerts` → phone |
| **Expected detection time** | ~3 min (15s scrape + 2m `for` + 30s `group_wait`) |
| **Does NOT cover** | The blackbox exporter itself being down (that's **TargetDown**, job `blackbox`); the whole NAS being down (**TargetDown** for its exporters fires too); slow but working pages; a missed nightly backup (that's the healthchecks.io check) |

## How the check works

The **blackbox exporter** on the Beelink acts like a visitor: every 15 s it loads the BookStack login page and reports `probe_success` (1 = page loaded with a 2xx, 0 = it didn't). Because it loads a real page, it catches a broken database too, not just a stopped container.

| Piece | Where | Details |
|---|---|---|
| BookStack | NAS, `nas/bookstack/compose.yml` | Container `bookstack`, port 6875 (LAN + Tailscale only in UFW) |
| Database | NAS, same compose file | Container `bookstack-db` (MariaDB 11.8), no published port |
| Data | NAS NVMe | `/opt/appdata/bookstack/config` (uploads, settings), `/opt/appdata/bookstack/db` (database files) |
| Secrets | NAS, `nas/bookstack/.env` (git-ignored) | `APP_KEY`, `DB_PASSWORD`, `DB_ROOT_PASSWORD` — copies in the password manager |
| Probe | Beelink, `monitoring/` compose | `blackbox` container, module `http_2xx` |
| Scrape job | Beelink, `prometheus.yml` | `job_name: blackbox-http` |
| Backups | NAS, `nas/bookstack/backup.sh`, cron 03:15 (Ansible) | `/tank/backups/bookstack/<date>/` → `db.sql.gz` + `config.tar.gz`, keep 7 |

---

## 1. Confirm (1 min)

From the Beelink — what does the probe see?

```bash
curl -s "http://localhost:9115/probe?target=http://100.105.219.6:6875/login&module=http_2xx&debug=true" | tail -20
```

From the NAS:

```bash
ssh nas
cd /opt/stacks/nas/bookstack
docker compose ps                       # both running? db "healthy"?
curl -I http://localhost:6875/login     # 200 = BookStack itself is fine
```

## 2. Diagnose

```bash
docker compose logs --tail=50 bookstack
docker compose logs --tail=50 bookstack-db
df -h /opt/appdata                      # NVMe full?
```

| What you see | Usually means |
|---|---|
| `bookstack` not running / restarting | App crashed or bad config — read its logs |
| `bookstack-db` not healthy | Database won't start: disk full, corrupted files, wrong password in `.env` |
| `curl` on the NAS gives **500** | BookStack is up but can't reach the database (`SQLSTATE` errors in logs) |
| `curl` on the NAS works, the probe fails | Network between the Beelink and the NAS: Tailscale down, UFW rule for 6875 missing |
| Both containers fine, page loads, alert still firing | The probe's URL or module is wrong — check the debug output above |
| Logs mention `APP_KEY` / "The MAC is invalid" | `APP_KEY` in `.env` changed or is missing |

## 3. Fix

| Cause | Fix |
|---|---|
| Container stopped/crashed | `docker compose up -d` (in `nas/bookstack`) |
| Database not healthy | `docker compose restart bookstack-db`, then watch its logs. Disk full → free space on `/opt/appdata` |
| Bad `.env` | Restore the values from the password manager, `docker compose up -d` |
| Network / UFW | `tailscale status` on both machines; `sudo ufw status numbered \| grep 6875` |
| Database files damaged | **Restore from backup** (below) |

### Restore from backup

1. Pick a backup: `ls -1 /tank/backups/bookstack/`
2. Stop the app (leave the database running): `docker compose stop bookstack`
3. Load the dump (it recreates the `bookstack` database):
   ```bash
   B=/tank/backups/bookstack/<chosen-date>
   zcat "$B/db.sql.gz" | docker exec -i bookstack-db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot'
   ```
4. Uploaded images and attachments, if they're lost too:
   ```bash
   sudo tar -xzf "$B/config.tar.gz" -C /opt/appdata/bookstack/config
   ```
5. Start it: `docker compose up -d`, log in, open a page with an image.

**Don't:** delete `/opt/appdata/bookstack/db` "to start fresh" (that wipes every page); change `APP_KEY` (logins and MFA break); publish the database port; port-forward 6875 to the internet.

## 4. Verify (the incident isn't over until all are true)

- [ ] `docker compose ps` → `bookstack` running, `bookstack-db` healthy
- [ ] `http://nas:6875` loads and you can log in
- [ ] A recent page and an image on it open correctly
- [ ] Prometheus → Alerts → `BookStackDown` **Inactive**
- [ ] **`[RESOLVED] BookStackDown` arrived on the phone**

## 5. Follow up

- [ ] Real outage? Postmortem in `docs/postmortems/YYYY-MM-DD-<name>.md`
- [ ] Restored from backup? Note how much was lost (time since the last 03:15 backup)
- [ ] Row in the History table below + the brag doc's Incidents table
- [ ] Step missing or wrong? Fix this runbook and commit

## History

| Date | What happened | Detect | Down for | Postmortem |
|---|---|---|---|---|
| 2026-11-19 | Broken compose.yml during port re-bind took BookStack down | ~3 min (FIRING 3:56 PM) | ~8 min (RESOLVED 4:01 PM) | — |
