# Runbook: DiskSpaceLow / PoolSpaceLow / DiskWillFillIn24h

| | |
|---|---|
| **Alerts** | `DiskSpaceLow` (warning) — an ext4 disk (`/` on either machine, `/opt/appdata`) under 15% free for 15m · `PoolSpaceLow` (warning) — ZFS pool `tank` under 7 TiB free (~15%) for 15m · `DiskWillFillIn24h` (critical) — an ext4 disk or the pool will be full within 24h at the last 6 hours' rate |
| **Rules** | `monitoring/prometheus/rules/alerts.yml` (node_exporter `node_filesystem_*`) |
| **Impact** | **NVMe (`/opt/appdata`, OS)** full → databases stop writing: Vaultwarden, BookStack, Immich, Jellyfin, *arr apps break, Minecraft can corrupt its world. **Pool (`/data`, `/tank/...`)** full → downloads, photo uploads and backups fail; ZFS gets slow above ~80–90% full |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy `homelab-alerts` → phone |
| **Does NOT cover** | A drive failing (DriveFailing / ZpoolNotOnline); inode exhaustion on non-ZFS filesystems |
| **Why the pool is different** | Every ZFS dataset reports the **pool's** free space, and a dataset's "size" is its own data + that free space, so percent-free per dataset is misleading. The pool is watched once, through `/tank`, in TiB |

## Where space goes

| Mount | Usual growth | Normal size |
|---|---|---|
| `/data` (tank/data) | Media library, Usenet downloads | Grows with requests — by design |
| `/data/usenet/incomplete`, `/complete` | Stuck or failed downloads that never imported | Should be near empty when idle |
| `/tank/photos` | Immich uploads + its DB dumps | Grows slowly |
| `/tank/backups` | Minecraft, BookStack, Vaultwarden archives | Flat (rotation keeps N) |
| `/opt/appdata` (NVMe) | App databases, Jellyfin metadata/transcode cache, Minecraft world | Slow growth |
| `/` (OS NVMe) | Docker images and container logs, system logs | Should be flat |

---

## 1. Confirm (1 min)

The alert's `mountpoint` and `instance` labels say which disk and which machine.

```bash
ssh nas            # or beelink
df -h
zfs list -o name,used,avail,refer,mountpoint     # NAS: per-dataset usage
```

## 2. Find what's using it

```bash
sudo du -xh --max-depth=2 <mountpoint> 2>/dev/null | sort -h | tail -20
```

Common spots:

```bash
du -sh /data/usenet/* /data/media/*                      # downloads vs library
du -sh /opt/appdata/* | sort -h | tail                   # biggest app folders
du -sh /opt/appdata/media/jellyfin/* 2>/dev/null | sort -h | tail   # transcodes/cache
docker system df                                          # images, containers, volumes
sudo journalctl --disk-usage                              # system logs
```

| What you see | Usually means |
|---|---|
| `/data/usenet/complete` large | Imports failing — Radarr/Sonarr → Activity → Queue shows why |
| `/data/usenet/incomplete` large | Stuck/failed downloads — check SABnzbd History |
| `/data/media` growing fast | Lots of requests, or Remux/4K-sized grabs — check Seerr requests and profiles |
| Jellyfin `transcodes` / `cache` large | Transcode leftovers or trickplay/chapter images |
| `docker system df` shows many GB reclaimable | Old images after upgrades |
| A container's log huge (`/var/lib/docker/containers/*/*-json.log`) | A crash-looping app writing logs nonstop |
| `/tank/backups` growing | Backup rotation not deleting — check the script's log |

## 3. Fix

| Cause | Fix |
|---|---|
| Stuck downloads | Fix the import error, or remove the item in SABnzbd/Radarr/Sonarr (with "remove files") |
| Old Docker images | `docker image prune -a` (only removes images no container uses) |
| Huge container log | Fix the crashing app; `sudo truncate -s 0 <that -json.log>`; consider log limits in compose (`logging: { options: { max-size: "10m", max-file: "3" } }`) |
| Jellyfin cache/transcodes | Dashboard → Scheduled Tasks → clean transcode directory / cache; turn off trickplay/chapter images if on |
| System logs | `sudo journalctl --vacuum-size=500M` |
| Library genuinely full | Remove media nobody watches (Jellystat shows what's unwatched); lower request limits; prefer smaller profiles |
| Backups not rotating | Check that backup script's log and KEEP value |

**Don't:** delete files inside app config folders or databases to free space; `rm -rf` anything under `/data/media` without checking it's not in use; delete ZFS snapshots/datasets you don't recognise; let the NVMe hit 100% (fix that one first — it breaks every database).

## 4. Verify

- [ ] `df -h` shows the mount back above 15% free
- [ ] The growth has stopped (Grafana → Node Exporter Full → Disk space, last 24h)
- [ ] Prometheus → Alerts → `DiskSpaceLow` / `DiskWillFillIn24h` **Inactive**
- [ ] **`[RESOLVED]` arrived on the phone**

## 5. Follow up

- [ ] Recurring? Add the permanent fix (log size limits, smaller profiles, lower request limits)
- [ ] Pool past ~70% used? Start planning more storage
- [ ] Row in the History table below + brag doc Incidents table
- [ ] Step missing or wrong? Fix this runbook and commit

## History

| Date | Machine / mount | What filled it | Fix | Postmortem |
|---|---|---|---|---|
| | | | | |
