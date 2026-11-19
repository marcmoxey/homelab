#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"                                   # NEW: "hourly" or "daily" from the command line
case "$MODE" in                                 # NEW: pick how many to keep
  hourly) KEEP=24 ;;
  daily)  KEEP=7  ;;
  *) echo "usage: $0 hourly|daily" >&2; exit 2 ;;
esac

SERVER="prominence2"
SRC="/opt/appdata/minecraft/prominence"
DEST="/tank/backups/minecraft/${SERVER}/${MODE}" # CHANGED: separate hourly/ and daily/ folders
TS="$(date +%F_%H-%M-%S)"
FILE="${DEST}/${SERVER}_${MODE}_${TS}.tar.gz"   # NEW: e.g. prominence2_hourly_2026-11-18_10-00-00.tar.gz

log() { echo "$(date '+%F %T') [${MODE}] $*"; } # NEW: every log line gets a timestamp + mode
rcon() { docker exec "$SERVER" rcon-cli "$@"; }

# NEW: only one backup at a time. If another run is still going (e.g. hourly
# and daily overlap), wait up to 10 minutes for it to finish, then give up.
exec 9>/tmp/mc-backup-${SERVER}.lock
if ! flock -w 600 9; then
  log "another backup is still running after 10 min; skipping"
  exit 1
fi

# NEW: server must be running, or rcon fails.
if ! docker ps --format '{{.Names}}' | grep -qx "$SERVER"; then
  log "container ${SERVER} is not running; skipping"
  exit 1
fi

mkdir -p "$DEST"

# Turn saving back on no matter how the script exits.
trap 'rcon save-on >/dev/null 2>&1 || true' EXIT

log "start → ${FILE}"                           # NEW
rcon save-off >/dev/null
rcon save-all flush >/dev/null

# Whole server folder minus things the image re-downloads or that aren't needed.
tar -czf "${FILE}.part" -C "$SRC" \
    --exclude=./logs \
    --exclude=./libraries \
    --exclude=./versions \
    --exclude='./*.jar' \
    .                                           # CHANGED: whole folder, writes to .part first
mv "${FILE}.part" "$FILE"                       # NEW: only a finished archive gets the real name

rcon save-on >/dev/null

# Keep only the newest $KEEP archives for this mode.
ls -1t "$DEST"/"${SERVER}_${MODE}_"*.tar.gz 2>/dev/null \
  | tail -n +$((KEEP + 1)) \
  | xargs -r rm --

log "ok $(du -h "$FILE" | cut -f1) — $(ls -1 "$DEST"/*.tar.gz | wc -l)/${KEEP} kept"   # NEW

# NEW (optional): ping healthchecks.io if ~/.mc-backup-hc-hourly or -daily exists.
HC_FILE="$HOME/.mc-backup-hc-${MODE}"
if [[ -f "$HC_FILE" ]]; then
  curl -fsS -m 10 --retry 3 "$(cat "$HC_FILE")" >/dev/null || log "healthchecks ping failed"
fi
