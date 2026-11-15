# Runbook: DriveHot

| | |
|---|---|
| **Alert** | `DriveHot` (warning): drive over 50 °C for 10 min |
| **Source** | smartctl_exporter on the NAS → Prometheus on the Beelink |
| **Impact** | Not urgent below ~60 °C (Exos rated max), but sustained heat shortens drive life |

## 1. Confirm
- Prometheus query: `smartctl_device_temperature{temperature_type="current"}`
- Which drives? One hot drive = that bay; all hot = airflow or room

## 2. Diagnose
- Are the rear fans spinning? Tissue test at the grille: air should blow OUT
- Is something heavy running (burn-in, scrub, resilver)? Expected to be warmer
- Fans following CPU temp in BIOS → slow when CPU is idle

## 3. Fix
| Cause | Fix |
|---|---|
| Fans slow | BIOS → Hardware Monitor → drive-fan headers to fixed 70–100% (needs reboot — not during burn-in/resilver) |
| Short-term, can't reboot | Desk fan at the case front, or side panel off |
| Fans wrong direction | Flip so spec stickers face the grille (exhaust) |

## 4. Verify
- All drives under 45 °C under load; alert returns to Inactive

## History
| Date | What happened | Peak | Fix |
|---|---|---|---|
| 2026-11-15 | Burn-in (badblocks): sda/sdb hit 51 °C | 51 °C | Desk fan / side panel; BIOS fan curve after burn-in |
