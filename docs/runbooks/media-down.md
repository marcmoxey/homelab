# Runbook: Media app down (Jellyfin, Seerr, *arr, SABnzbd, Bazarr, Clonarr, Jellystat)

| | |
|---|---|
| **Alert** | `ServiceDown{service="<app>"}` — jellyfin, seerr, sonarr, radarr, prowlarr, sabnzbd, bazarr, clonarr, jellystat |
| **Rule** | `probe_success == 0` for 2m — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | The Beelink can't load that app's health page on `100.105.219.6:<port>` for 2 minutes |
| **Impact** | Depends on the app (table below). Nothing is lost while it's down: media is on the pool, settings on the NVMe |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy `homelab-alerts` → phone |
| **Expected detection time** | ~3 min |
| **Does NOT cover** | Public access via Caddy (→ [caddy-down.md](caddy-down.md)); downloads failing while the apps are up (check Radarr/Sonarr → Activity); the pool being degraded (ZpoolNotOnline) |

## Which app, what breaks

| Service label | Container | Probe | If it's down |
|---|---|---|---|
| jellyfin | `jellyfin` | `:8096/health` | **Nobody can watch** (home or away) — highest priority |
| seerr | `seerr` | `:5055/api/v1/status` | Friends/family can't request |
| sonarr / radarr | `sonarr` / `radarr` | `:8989/ping` / `:7878/ping` | New TV / movies stop downloading and importing |
| prowlarr | `prowlarr` | `:9696/ping` | Searches return nothing (Sonarr/Radarr have no indexers) |
| sabnzbd | `sabnzbd` | `:8085` | Downloads stop; queue resumes when it's back |
| bazarr | `bazarr` | `:6767` | No new subtitles |
| clonarr | `clonarr` | `:6060` | No profile syncs (no immediate effect) |
| jellystat | `jellystat` | `:3001` | Stats only |

All live in one stack: `/opt/stacks/nas/media` (details: [docs/media.md](../media.md)).

---

## 1. Confirm (1 min)

```bash
ssh nas
cd /opt/stacks/nas/media
docker compose ps                                   # which one isn't "Up"?
docker inspect <container> --format 'restarts={{.RestartCount}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}}'
docker compose logs --tail=50 <container>
```

## 2. Diagnose

| What you see | Usually means |
|---|---|
| `Exited (0)` | Stopped on purpose (drill, or someone ran `stop`) — `restart: unless-stopped` won't bring it back |
| `Restarting` / non-zero exit | Crash loop — the logs say why |
| `oom=true` | Ran out of memory (Jellyfin transcoding, Jellyfin/Immich ML) — `free -h`, `docker stats --no-stream` |
| Logs: `database is locked` / `malformed` | App's SQLite DB damaged — restore its config (below) |
| Logs: permission denied on `/data` or `/config` | Ownership changed — `ls -ln` should show 1000:1000 |
| Up, but probe fails | Port binding changed, or Tailscale between Beelink and NAS |
| All media apps down together | `/data` missing (pool not mounted → ZpoolNotOnline) or the NAS itself |
| Jellyfin up, playback fails | `/dev/dri` missing (iGPU) — check Dashboard → Playback, logs mention `vaapi`/`qsv` |

## 3. Fix

| Cause | Fix |
|---|---|
| Stopped | `docker compose up -d <service>` |
| Crash after an update | Put the previous pinned tag back in `compose.yml`, `docker compose up -d <service>`; read the release notes |
| Out of memory | Restart it; if it repeats, set `mem_limit` or reduce concurrent transcodes |
| Damaged app DB (*arr) | `docker compose stop <service>`; restore its latest built-in backup from `/opt/appdata/media/<app>/Backups/` (System → Backup in the app, or unzip over `/config`); start |
| Permissions | `sudo chown -R 1000:1000 /opt/appdata/media/<app>` (and `/data/media` / `/data/usenet` if those changed) |
| Pool / `/data` missing | Follow [zpool-not-online.md](zpool-not-online.md) first, then `docker compose up -d` |

**Don't:** `docker compose down` the whole stack to fix one app (it takes Jellyfin and Caddy down
for everyone); delete an app's `/config` to "start fresh" (loses all its settings, API keys and history).

## 4. Verify

- [ ] `docker compose ps` → the app is Up
- [ ] Its page loads at `http://nas:<port>` and it shows its normal data
- [ ] Jellyfin: a video plays; *arr: Activity shows nothing stuck; SABnzbd: queue moving
- [ ] Prometheus → Alerts → `ServiceDown` for that service **Inactive**
- [ ] **`[RESOLVED] ServiceDown` arrived on the phone**

## 5. Follow up

- [ ] Real outage of Jellyfin or Seerr? Postmortem in `docs/postmortems/YYYY-MM-DD-<name>.md`
- [ ] Row in the History table below + the brag doc's Incidents table
- [ ] Step missing or wrong? Fix this runbook and commit

## History

| Date | App | What happened | Detect | Down for | Postmortem |
|---|---|---|---|---|---|
| 2026-11-20 | jellyfin | Drill (repeat): stopped container | FIRING 12:57 PM | ~8 min (RESOLVED ~1:05 PM) | — |
| 2026-11-20 | jellyfin | Drill: stopped container to test ServiceDown (critical) | FIRING 12:31 PM | ~5 min (RESOLVED 12:36 PM) | — |
