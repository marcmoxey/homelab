# Runbook: ZpoolNotOnline

| | |
|---|---|
| **Alert** | `ZpoolNotOnline` (severity: critical) |
| **Rule** | `node_zfs_zpool_state{state="online"} == 0` for 1m — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | The ZFS pool `tank` is DEGRADED, FAULTED, SUSPENDED or UNAVAIL |
| **Impact** | **DEGRADED:** everything still works, but RAIDZ1 has **no redundancy left** — one more drive failure loses the pool. **FAULTED/SUSPENDED:** the pool is unusable; services reading `/data` or `/tank` fail |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy `homelab-alerts` → phone |
| **Expected detection time** | ~2 min (15s scrape + 1m `for` + 30s `group_wait`) |
| **Does NOT cover** | Checksum errors that ZFS repaired while staying ONLINE (see `zpool status` CKSUM column / monthly scrub); a drive getting sick before it drops out (that's **DriveFailing** / SMART counters) |

## How the check works

node_exporter on the NAS reads the pool state from the kernel and reports one line per state; exactly one is `1`. Prometheus scrapes it every 15 s.

| Piece | Where | Details |
|---|---|---|
| Pool `tank` | NAS | RAIDZ1, 4× Seagate Exos 18 TB, by-id device names |
| node_exporter | NAS, `nas/exporters/compose.yaml` | `100.105.219.6:9100`, metric `node_zfs_zpool_state` |
| Scrape job | Beelink, `prometheus.yml` | `job_name: node` |

**Drive map** (serial is printed on the drive label; bay numbers in `docs/hardware.md`):

| by-id name | Serial | Bay |
|---|---|---|
| `ata-ST18000NM003D-3DL103_ZVTD50NM` | ZVTD50NM | ? |
| `ata-ST18000NM003D-3DL103_ZVT6HX41` | ZVT6HX41 | ? |
| `ata-ST18000NM003D-3DL103_ZVTCXXPL` | ZVTCXXPL | ? |
| `ata-ST18000NM003D-3DL103_ZVTCPE09` | ZVTCPE09 | ? |

---

## 1. Confirm (1 min)

```bash
ssh nas
zpool status -x            # "all pools are healthy" = false alarm / already recovered
zpool status tank          # which drive is not ONLINE, and the READ/WRITE/CKSUM counts
```

**Before anything else when DEGRADED:** you have no redundancy. Don't start big copies, don't reboot unless you must, and check when the last off-site backup ran.

## 2. Diagnose

| Pool state | Drive state | Usually means |
|---|---|---|
| DEGRADED | one drive `FAULTED` (many errors) | Drive is failing |
| DEGRADED | one drive `UNAVAIL` / `REMOVED` | Drive or its cable/port disappeared (loose SATA/power cable, backplane, HBA) |
| DEGRADED | one drive `OFFLINE` | Someone ran `zpool offline` (a drill?) |
| ONLINE but CKSUM > 0 | — | Bad data read and repaired; watch that drive |
| FAULTED / SUSPENDED | two+ drives missing | Stop. Power/cable/HBA problem affecting several drives, or a second failure |

Check the drive that's not ONLINE:

```bash
ls -l /dev/disk/by-id/ | grep ZVT | grep -v part        # is it still visible to Linux?
sudo smartctl -a /dev/disk/by-id/<its-by-id-name> | grep -E "SMART overall|Reallocated|Pending|Offline_Uncorrectable|UDMA_CRC|Temperature"
sudo dmesg -T | grep -iE "ata[0-9]|I/O error|reset" | tail -30
```

| What you see | Means |
|---|---|
| Drive missing from `by-id` | Not connected / not detected — cable, power, bay |
| `UDMA_CRC_Error_Count` rising | Bad cable or connection, usually not the drive |
| Reallocated / Pending / Uncorrectable > 0, or SMART FAILED | The drive itself is dying |
| `dmesg` full of resets on one `ata` port | Cable/port problem |

## 3. Fix

| Cause | Fix |
|---|---|
| Drill (`zpool offline`) | `sudo zpool online tank <by-id-name>` |
| Loose cable / drive reseated | Power down, reseat SATA + power for that bay, boot. Then `sudo zpool online tank <by-id-name>` if needed and `sudo zpool clear tank` |
| Drive is failing | **Replace it** (below) |
| Several drives missing at once | Power down. Check the PSU cables, backplane, HBA. Do **not** run `zpool replace` on multiple drives |

### Replace a failed drive

1. **Find it physically:** match the serial from `zpool status` to the drive label / `docs/hardware.md` bay.
2. **If it's still responding, take it offline first:** `sudo zpool offline tank <old-by-id-name>`
3. Power down, swap the drive in the same bay, boot.
4. **New drive check** — ideally a full burn-in first; under pressure at least: `sudo smartctl -t short /dev/disk/by-id/<new-by-id-name>` and check the result.
5. **Replace:**
   ```bash
   ls -l /dev/disk/by-id/ | grep -v part                       # find the new drive's by-id name
   sudo zpool replace tank <old-by-id-name> /dev/disk/by-id/<new-by-id-name>
   ```
6. **Watch the resilver** (rebuild from parity — can take many hours on 18 TB):
   ```bash
   watch -n 60 zpool status tank
   ```

**Don't:** use `/dev/sdX` names (they change between boots — always by-id); run `zpool replace` on the wrong drive; reboot or pull another drive during a resilver; run `zpool clear` on a drive that SMART says is failing (it hides the problem, doesn't fix it).

## 4. Verify (the incident isn't over until all are true)

- [ ] `zpool status tank` → **state: ONLINE**, resilver finished with **0 errors**
- [ ] `zpool status -x` → `all pools are healthy`
- [ ] Prometheus → Alerts → `ZpoolNotOnline` **Inactive**
- [ ] **`[RESOLVED] ZpoolNotOnline` arrived on the phone**
- [ ] Run a scrub to double-check everything: `sudo zpool scrub tank` → finishes with 0 errors
- [ ] New drive's serial and bay recorded in `docs/hardware.md`

## 5. Follow up

- [ ] Real failure or drill? Postmortem in `docs/postmortems/YYYY-MM-DD-<name>.md`
- [ ] Failed drive under warranty? Seagate RMA with the serial and SMART output
- [ ] Row in the History table below + the brag doc's Incidents table
- [ ] Step missing or wrong? Fix this runbook and commit

## History

| Date | What happened | Detect | Down for | Postmortem |
|---|---|---|---|---|
| | | | | |
