# Runbook: ServiceDown — Immich

| | |
|---|---|
| **Alert** | `ServiceDown{service="immich"}` (severity: warning) |
| **Rule** | `probe_success == 0` for 2m — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | The Beelink can't get an answer from `http://100.105.219.6:2283/api/server/ping` for 2 minutes |
| **Impact** | Photos can't be viewed or uploaded. **Nothing is lost:** phones keep their photos and upload them when Immich is back (phone cloud backup is still on as the main copy) |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy `homelab-alerts` → phone |
| **Expected detection time** | ~3 min (15s scrape + 2m `for` + 30s `group_wait`) |
| **Does NOT cover** | The machine-learning container being down (the site still answers; only face recognition and smart search break — check `docker compose ps`); the pool being degraded (**ZpoolNotOnline**); the NAS down (**TargetDown**); missed backups |

## How the check works

`/api/server/ping` is Immich's built-in health check; it answers `{"res":"pong"}` when the server is up. The blackbox exporter on the Beelink asks for it every 15 s.

| Piece | Where | Details |
|---|---|---|
| Immich (4 containers) | NAS, `nas/immich/docker-compose.yml` + `.env` | `immich_server` (web + API), `immich_machine_learning` (faces, search), `immich_redis` (job queue), `immich_postgres` (database) |
| Port | `192.168.0.231:2283` and `100.105.219.6:2283` | LAN + Tailscale only (bound to those IPs; UFW rules as well) |
| Photos and videos | ZFS pool, `/tank/photos` (`UPLOAD_LOCATION`) | Originals, thumbnails, encoded videos |
| Database | NAS NVMe, `/opt/appdata/immich/postgres` (`DB_DATA_LOCATION`) | Albums, faces, people, metadata — **must stay on local disk, never a network share** |
| Database backups | `/tank/photos/backups/` | Immich's built-in nightly database dumps (Administration → Settings → Backup) |
| Version | `IMMICH_VERSION` in `.env` | All four containers must run the same version |
| Probe | Beelink, `prometheus.yml` job `blackbox-http` | Label `service: immich` |

**Important:** the database and the photos are a pair. The database knows *about* the photos (albums, faces); the files are the photos. A restore needs both from roughly the same time.

---

## 1. Confirm (1 min)

From the Beelink:

```bash
docker exec prometheus wget -qO- "http://blackbox:9115/probe?target=http://100.105.219.6:2283/api/server/ping&module=http_2xx&debug=true" | head -40
```

On the NAS:

```bash
ssh nas
cd /opt/stacks/nas/immich
docker compose ps                                     # all 4 running? server + postgres (healthy)?
curl -s http://100.105.219.6:2283/api/server/ping     # expect {"res":"pong"}
```

## 2. Diagnose

```bash
docker compose logs --tail=50 immich-server
docker compose logs --tail=30 database
zpool status -x                    # is the pool healthy?
ls /tank/photos | head             # is the photo folder there?
df -h /opt/appdata /tank/photos
```

| What you see | Usually means |
|---|---|
| `immich_server` restarting, logs mention `.immich` files or "folder checks failed" | `/tank/photos` isn't there — pool not imported/mounted, or the path in `.env` is wrong |
| `immich_postgres` not healthy | Database won't start: NVMe full, damaged files, wrong `DB_PASSWORD` |
| Server logs: can't connect to database / redis | Those containers are down — start them first |
| Right after an upgrade, server won't start | Version mismatch or a migration problem — check the release notes for that version |
| Everything fine on the NAS, probe fails | Network between the Beelink and NAS (Tailscale), or the port binding changed |
| Site works but faces / search don't | `immich_machine_learning` is down — not this alert, but restart it |

## 3. Fix

| Cause | Fix |
|---|---|
| Containers stopped/crashed | `docker compose up -d` (in `nas/immich`) |
| Pool not mounted | Follow **zpool-not-online.md**; once `/tank/photos` is back, `docker compose restart immich-server` |
| Database down | `docker compose restart database`, read its logs; disk full → free space on `/opt/appdata` |
| Bad upgrade | Put the previous `IMMICH_VERSION` back in `.env` **only if the release notes say it's safe** (database migrations may not go backwards); otherwise restore the database from the dump taken before the upgrade |
| Database damaged | **Restore the database** (below) |

### Restore the database (photos are still fine)

Follow the official **Backup and Restore** page (immich.app docs) for your version — the steps can change between releases. The usual shape:

```bash
cd /opt/stacks/nas/immich
ls -1t /tank/photos/backups/ | head          # newest dump first
docker compose down
sudo mv /opt/appdata/immich/postgres /opt/appdata/immich/postgres.broken-$(date +%F)
docker compose create
docker start immich_postgres
sleep 10
gunzip --stdout /tank/photos/backups/<chosen-dump>.sql.gz \
  | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
  | docker exec -i immich_postgres psql --dbname=postgres --username=postgres
docker compose up -d
```

Then open Immich, check albums and people, and open a few photos.

**Don't:** delete or move anything in `/tank/photos` to "fix" Immich (that's your photo library); point `DB_DATA_LOCATION` at the pool or a network share; run different versions of the containers; use "Free up space" on the phone until off-site backups (B2) exist; publish 2283 on `0.0.0.0` or port-forward it.

## 4. Verify (the incident isn't over until all are true)

- [ ] `docker compose ps` → all 4 running, server and database **(healthy)**
- [ ] `curl -s http://100.105.219.6:2283/api/server/ping` → `{"res":"pong"}`
- [ ] Web: log in, open a recent photo, an album and the People page
- [ ] Phone app: backup screen shows it's uploading / up to date
- [ ] Prometheus → Alerts → `ServiceDown` for immich **Inactive**
- [ ] **`[RESOLVED] ServiceDown` (immich) arrived on the phone**

## 5. Follow up

- [ ] Real outage? Postmortem in `docs/postmortems/YYYY-MM-DD-<name>.md`
- [ ] Restored the database? Note how much was lost (albums/faces since the dump)
- [ ] Row in the History table below + the brag doc's Incidents table
- [ ] Step missing or wrong? Fix this runbook and commit

## History

| Date | What happened | Detect | Down for | Postmortem |
|---|---|---|---|---|
| 2026-11-19 | Deployed on the Beelink by mistake; probe found nothing on the NAS | Fired 5:33 PM | ~15 min (RESOLVED 5:48 PM) | — |
