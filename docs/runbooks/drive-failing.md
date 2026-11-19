# Runbook: DriveFailing

| | |
|---|---|
| **Alert** | `DriveFailing` (severity: critical) |
| **Rule** | `smartctl_device_smart_status != 1` for 5m — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | A drive's own SMART self-assessment says **FAILED** — the drive itself predicts it will fail soon |
| **Impact** | Nothing lost yet, but the drive can die any time. **Pool drive:** losing it leaves `tank` with no redundancy. **NVMe (`/opt/appdata`):** the live Minecraft world and app data are at risk. **NVMe (OS):** the NAS may stop booting |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy `homelab-alerts` → phone |
| **Expected detection time** | ~6 min (15s scrape + 5m `for` + 30s `group_wait`) |
| **Does NOT cover** | A drive that's getting worse but still says PASSED (watch the **warning counters** on the Drives dashboard); a drive that has already dropped out of the pool (that's **ZpoolNotOnline**); heat (that's **DriveHot**) |

## How the check works

smartctl-exporter on the NAS asks every drive for its SMART report and publishes `smartctl_device_smart_status` (1 = PASSED, 0 = FAILED). Prometheus scrapes it.

| Piece | Where | Details |
|---|---|---|
| smartctl-exporter | NAS, `nas/exporters/compose.yaml` | `100.105.219.6:9633`, privileged, scans all drives |
| Scrape job | Beelink, `prometheus.yml` | `job_name: smartctl` |
| Dashboard | Grafana → **Drives (SMART)** | Health, temperature, warning counters, NVMe wear |

**Which drive is which:**

| Device | Drive | What's on it |
|---|---|---|
| `sda`–`sdd` (letters can change — use the serial) | 4× Seagate Exos 18 TB (ZVTD50NM, ZVT6HX41, ZVTCXXPL, ZVTCPE09) | ZFS pool `tank`: media, files, photos, **backups** |
| `nvme0n1` | Samsung 990 EVO Plus 1 TB | `/opt/appdata`: live Minecraft world, app data |
| `nvme1n1` | Inland 512 GB | Ubuntu (the OS) |

Bays for each serial: `docs/hardware.md`.

---

## 1. Confirm (2 min)

The alert's `device` label names the drive.

```bash
ssh nas
sudo smartctl -H /dev/<device>                     # overall: PASSED or FAILED
sudo smartctl -a /dev/<device> | less              # full report
```

For a hard drive, look at:

```bash
sudo smartctl -A /dev/<device> | grep -E "Reallocated_Sector|Current_Pending|Offline_Uncorrectable|Reported_Uncorrect|UDMA_CRC|Temperature"
```

For an NVMe drive:

```bash
sudo smartctl -a /dev/<device> | grep -E "Critical Warning|Percentage Used|Available Spare|Media and Data Integrity Errors"
```

## 2. Diagnose

| What you see | Means |
|---|---|
| `SMART overall-health: FAILED` | Believe it. The drive is dying — plan the replacement now |
| Reallocated / Pending / Uncorrectable counters > 0 and rising | Surface going bad (hard drive) |
| Only `UDMA_CRC_Error_Count` rising | Usually a bad cable, not the drive — reseat/replace the SATA cable |
| NVMe `Critical Warning` not 0, `Available Spare` near its threshold, or `Percentage Used` near 100% | SSD worn out or failing |
| NVMe `Media and Data Integrity Errors` > 0 | SSD has failed to read/write data |
| `smartctl` can't read the drive at all | Drive already dead or disconnected — check `zpool status` / `dmesg` |

## 3. Fix — depends on which drive

**First, for every case: make sure the data on it has a good copy.**

### A pool hard drive (sda–sdd)

1. `zpool status tank` — is the pool still ONLINE?
2. Check the off-site backup is recent before touching anything.
3. Replace it before it dies: follow **[zpool-not-online.md](zpool-not-online.md) → "Replace a failed drive"** (`zpool offline` → swap → `zpool replace` by-id → resilver).
4. Under warranty? Start a Seagate RMA with the serial and the SMART output.

### The appdata NVMe (`/opt/appdata`)

1. Make a fresh Minecraft backup right now (it goes to the pool, not this SSD): `/opt/stacks/nas/gameservers/minecraft/backup.sh daily`
2. Copy the rest of `/opt/appdata` to the pool: `rsync -a /opt/appdata/ /tank/backups/appdata-rescue/`
3. Replace the SSD, recreate the `appdata` filesystem and the fstab line (`LABEL=appdata`), restore with `rsync`, then `docker compose up -d` each stack.

### The OS NVMe

1. Make sure the repo is pushed and secrets are in the password manager (that's everything needed to rebuild).
2. Replace the SSD, install Ubuntu, run Ansible (`site.yml`), clone the repo to `/opt/stacks`, `zpool import tank`, restore secrets, `docker compose up -d` each stack.

**Don't:** ignore it because "everything still works"; wait for the drive to die before acting; use `/dev/sdX` names in `zpool` commands (always by-id).

## 4. Verify (the incident isn't over until all are true)

- [ ] The failing drive is out and the replacement shows `PASSED` in `smartctl -H`
- [ ] Grafana → Drives dashboard: all **PASSED**, warning counters **0**
- [ ] Pool drive: `zpool status tank` → ONLINE, resilver done, 0 errors
- [ ] NVMe: services back up, Minecraft joins, world is the latest backup
- [ ] Prometheus → Alerts → `DriveFailing` **Inactive**
- [ ] **`[RESOLVED] DriveFailing` arrived on the phone**
- [ ] New serial and bay recorded in `docs/hardware.md`

## 5. Follow up

- [ ] Postmortem in `docs/postmortems/YYYY-MM-DD-<name>.md` (how much warning did SMART give?)
- [ ] RMA sent? Note the case number in `docs/hardware.md`
- [ ] Consider an earlier-warning alert: any reallocated/pending sectors > 0 (catches drives *before* SMART says FAILED)
- [ ] Row in the History table below + the brag doc's Incidents table
- [ ] Step missing or wrong? Fix this runbook and commit

## History

| Date | What happened | Detect | Down for | Postmortem |
|---|---|---|---|---|
| | | | | |
