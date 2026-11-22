# Backups

Three copies of everything that can't be re-downloaded: the live data, a local backup on the
ZFS pool, and an encrypted off-site copy in Backblaze B2 (3-2-1).

```
02:00–04:00  local backups → /tank/backups, /tank/photos/backups   (per-app scripts, healthchecks pings)
05:00        restic → Backblaze B2 (encrypted on the NAS before upload)  (nas/restic/backup.sh, healthchecks ping)
```

## What is backed up where

| Data | Local backup | Off-site (B2) |
|---|---|---|
| Vaultwarden | `nas/vaultwarden/backup.sh` → `/tank/backups/vaultwarden/` (30 kept) | ✅ |
| BookStack (MariaDB + uploads) | `nas/bookstack/backup.sh` → `/tank/backups/bookstack/` (7 kept) | ✅ |
| Minecraft worlds | `backup.sh hourly/daily` → `/tank/backups/minecraft/<server>/` (24 hourly, 7 daily) | ✅ newest daily per server only (`/tank/backups/minecraft-latest/`, hardlinks) |
| Immich photos + DB dumps | Photos live on the pool (RAIDZ1); Immich's own DB dumps in `/tank/photos/backups/` | ✅ |
| Samba share | Lives on the pool | ✅ `/tank/files` |
| Music (`/data/media/music`) | Lives on the pool | ✅ (added to restic paths: owned files, not re-downloadable) |
| App settings (`/opt/appdata`) | *arr apps keep their own zips in `<app>/Backups/` | ✅ minus caches, logs, live Minecraft world |
| Media library (`/data`) | Not backed up (re-downloadable; ~$70/month per 10 TB in B2) | ❌ by design |
| Repo (compose, configs, docs) | GitHub | — |

Live database folders under `/opt/appdata` get copied too, but **restore databases from the dumps**,
not from those copies (a copy of a running database may be inconsistent).

## Off-site: restic → Backblaze B2

| Piece | Where |
|---|---|
| Bucket + key | Terraform, `terraform/b2/` (bucket private, SSE-B2 encryption, hidden versions deleted after 1 day). The key only works on this bucket |
| Connection settings | `/root/.restic.env` (repo URL, key ID, key), mode 600, **not in Git** |
| Encryption password | `/root/.restic-password`, mode 600. Copies: Vaultwarden **and the paper emergency sheet** |
| Script | `nas/restic/backup.sh`, root cron `0 5 * * *`, log `/var/log/restic-backup.log` |
| Excludes | `nas/restic/excludes.txt` |
| Retention | 7 daily, 4 weekly, 6 monthly (`forget --prune` every night) |
| Integrity | Sundays: `restic check --read-data-subset=5%` (re-downloads and verifies 5% of the data) |
| Missed/failed run | healthchecks.io check `restic-b2` (period 1 day, grace 2 h): the script pings `/start`, success, or `/fail` |
| Cost guard | B2 Caps & Alerts: storage $1/day, download $1/day; email alerts at 75% and 100% |
| Size | ~2.3 GiB stored (first snapshot 2026-11-21) ≈ well under $1/month |

The script treats restic exit code 3 ("a file vanished while reading", e.g. SQLite temp files) as a
warning, not a failure. It also uses `-o s3.connections=2`, because B2 rate-limits new accounts.

## Restore

Without the encryption password, nothing in B2 can be read. Recovery needs three things:
`/root/.restic.env` values (Vaultwarden item "B2 restic (NAS)"), the password (Vaultwarden / paper sheet),
and restic.

```bash
sudo -i
source /root/.restic.env
restic snapshots                                   # pick a snapshot (or use "latest")
restic ls latest /tank/backups/vaultwarden | tail  # see what's inside

# Restore into a scratch folder, never straight over live data
restic restore latest --target /tmp/restore --include /tank/backups/vaultwarden
ls -la /tmp/restore/tank/backups/vaultwarden/
```

Then follow that app's runbook to load the dump (e.g. `vaultwarden-down.md`, `bookstack-down.md`).

**NAS completely gone:** on any Linux machine, install restic, recreate `/root/.restic.env` and the
password file from Vaultwarden / the paper sheet, then `restic restore latest --target /restore`.
Downloads are free up to 3× the stored size.

## Restore tests

| Date | What | Result |
|---|---|---|
| 2026-11-21 | Vaultwarden archive restored from B2 (snapshot `41a30433`) into `/tmp/restore` | ✅ Byte-identical to the local copy (`diff`), archive opens (`db.sqlite3`, key, attachments). 461 vault items |

## Incident: Vaultwarden backups never ran (found by the first restore test)

The first B2 restore test found **no `/tank/backups/vaultwarden` at all**. The backup script existed
since 2026-11-19 but had never run, for three separate reasons, each enough on its own:

| Cause | Fix |
|---|---|
| No line in root's crontab | Added `45 3 * * * … >> /var/log/vaultwarden-backup.log 2>&1` |
| Script not executable (`Permission denied`, exit 126) | `chmod 755`, and `git update-index --chmod=+x` so a fresh clone keeps it |
| `sqlite3` not installed on the host (exit 127) | `apt install sqlite3`; added to the Ansible base packages |

**Why nothing alerted:** the healthchecks ping file was never created, and a healthchecks.io check
that has **never received a ping stays grey ("new") and never alerts**.

**Lessons:** a backup isn't real until it has been restored. After adding any scheduled job, run it
once by hand, confirm its check turns green, and confirm the output exists. Every healthchecks.io
check must be green; a grey one is a job that has never run.
