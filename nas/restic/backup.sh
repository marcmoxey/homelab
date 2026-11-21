#!/usr/bin/env bash
# Nightly off-site backup: restic -> Backblaze B2. Runs as root from cron.
set -uo pipefail

ENV_FILE=/root/.restic.env           # repo URL, B2 key, password file (not in Git)
HC_FILE=/root/.restic-hc             # healthchecks.io ping URL (not in Git)
EXCLUDES=/opt/stacks/nas/restic/excludes.txt
LOG=/var/log/restic-backup.log
PATHS=(/tank/backups /tank/photos /tank/files /opt/appdata)
OPTS=(-o s3.connections=2)           # gentle on B2 rate limits

exec >>"$LOG" 2>&1
echo "=== $(date -Is) start"
source "$ENV_FILE"
HC=$(cat "$HC_FILE" 2>/dev/null || true)
hc() { [ -n "$HC" ] && curl -fsS -m 10 --retry 3 -o /dev/null "$HC$1" || true; }
fail() { echo "FAILED: $1"; hc /fail; exit 1; }
hc /start

# 1. Newest daily Minecraft archive per server -> minecraft-latest (hardlinks, no extra space)
LATEST=/tank/backups/minecraft-latest
rm -rf "$LATEST" && mkdir -p "$LATEST"
for daily in /tank/backups/minecraft/*/daily; do
  server=$(basename "$(dirname "$daily")")
  newest=$(ls -t "$daily"/*.tar.gz 2>/dev/null | head -1)
  [ -n "$newest" ] && mkdir -p "$LATEST/$server" && ln "$newest" "$LATEST/$server/"
done

# 2. Backup. Exit 3 = a file vanished mid-scan (warning, not failure)
restic "${OPTS[@]}" backup "${PATHS[@]}" --exclude-file="$EXCLUDES" --tag nightly
rc=$?; [ $rc -ne 0 ] && [ $rc -ne 3 ] && fail "backup rc=$rc"

# 3. Retention: 7 daily, 4 weekly, 6 monthly
restic "${OPTS[@]}" forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || fail "forget/prune"

# 4. Sundays: re-download and verify 5% of the data
if [ "$(date +%u)" = 7 ]; then
  restic "${OPTS[@]}" check --read-data-subset=5% || fail "check"
fi

echo "=== $(date -Is) ok"
hc ""
