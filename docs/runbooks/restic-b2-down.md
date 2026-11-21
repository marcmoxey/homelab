# Runbook: Off-site backup failed or missed (restic → B2)

| | |
|---|---|
| **Alert** | healthchecks.io check `restic-b2` is **DOWN** (no ping by 05:00 + 2 h grace) or got a **/fail** ping |
| **Script** | `/opt/stacks/nas/restic/backup.sh` (root cron `0 5 * * *`), log `/var/log/restic-backup.log` |
| **Impact** | No data is lost: the local backups and live data are fine. The off-site copy is older than it should be. Fix within a few days |
| **Notified via** | healthchecks.io → email / Discord / ntfy.sh |
| **Details** | [docs/backups.md](../backups.md) |

## 1. Confirm

```bash
sudo tail -30 /var/log/restic-backup.log      # last run: "=== … ok" or "FAILED: …"
sudo crontab -l | grep restic                  # still scheduled?
sudo bash -c 'source /root/.restic.env && restic snapshots --latest 3'
```

## 2. Diagnose

| Log shows | Usually means |
|---|---|
| No entry for today | Cron didn't run: NAS was off, crontab changed, script not executable (`ls -l nas/restic/backup.sh`) |
| `FAILED: backup rc=1` + `Malformed Access Key Id` / `InvalidAccessKeyId` | B2 key wrong or deleted (`/root/.restic.env`) |
| `transaction_cap_exceeded` / `storage_cap_exceeded` | B2 Caps & Alerts limit hit: check B2 → Caps & Alerts, raise if the growth is expected |
| `too many requests` retried forever | B2 rate limiting: wait, or lower `s3.connections` to 1 |
| `repository is already locked` | A previous run was killed mid-way: check nothing else is running, then `restic unlock` |
| `wrong password or no key found` | `/root/.restic-password` changed or missing; restore it from Vaultwarden / paper sheet |
| `FAILED: check` | Data in B2 failed verification: run `restic check` (full) and investigate before the next prune |
| DNS / connection errors | NAS internet down at 05:00: rerun by hand |

## 3. Fix

| Cause | Fix |
|---|---|
| Key wrong/deleted | Recreate with Terraform (`terraform/b2`, `tf apply`), rewrite `/root/.restic.env` from `tf output` (cheatsheet → Terraform) |
| Stale lock | `sudo bash -c 'source /root/.restic.env && restic unlock'` |
| Cap hit | Raise the B2 cap, or exclude what grew unexpectedly in `nas/restic/excludes.txt` |
| Anything else | Fix the cause, then run it by hand: `sudo /opt/stacks/nas/restic/backup.sh; echo "exit=$?"` |

**Don't:** delete the bucket or snapshots to "start fresh"; change the restic password without updating
Vaultwarden and the paper sheet (old backups would become unreadable to you).

## 4. Verify

- [ ] `sudo tail -5 /var/log/restic-backup.log` ends with `=== … ok`
- [ ] `restic snapshots` shows a snapshot from today
- [ ] healthchecks.io `restic-b2` is **UP**

## History

| Date | What happened | Fix |
|---|---|---|
| | | |
