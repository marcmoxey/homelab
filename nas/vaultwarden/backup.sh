#!/usr/bin/env bash
# Vaultwarden backup: a consistent copy of the vault database + keys + attachments.
# Keeps the newest 30.
#
# Runs as ROOT (the data folder is owned by root). Install sqlite3 first:
#   sudo apt install sqlite3
#
# Each run makes one folder:
#   /tank/backups/vaultwarden/2026-11-19_03-45-00/
#       vaultwarden.tar.gz   db.sqlite3 (safe copy), rsa_key*, attachments/, sends/, config.json
#
# Restore = stop the container, extract this archive into /opt/appdata/vaultwarden, start it
# (see docs/runbooks/vaultwarden-down.md).
#
# The vault contents are encrypted with the master password on your devices, so this
# archive can't be read without it. Still: folder is root-only (700).
#
# cron (sudo crontab -e):
#   45 3 * * * /opt/stacks/nas/vaultwarden/backup.sh >> /var/log/vaultwarden-backup.log 2>&1

set -euo pipefail

SRC="/opt/appdata/vaultwarden"
DEST="/tank/backups/vaultwarden"
KEEP=30
TS="$(date +%F_%H-%M-%S)"
WORK="${DEST}/.${TS}.part"
FINAL="${DEST}/${TS}"
HC_FILE="/root/.vaultwarden-backup-hc"     # healthchecks.io ping URL (secret)

log() { echo "$(date '+%F %T') [vaultwarden] $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "run as root (sudo)" >&2
  exit 2
fi

exec 9>/tmp/vaultwarden-backup.lock
if ! flock -w 600 9; then
  log "another backup is still running after 10 min; skipping"
  exit 1
fi

if [[ ! -f "${SRC}/db.sqlite3" ]]; then
  log "no database at ${SRC}/db.sqlite3; skipping"
  exit 1
fi

trap 'rm -rf "$WORK"' EXIT
mkdir -p "$DEST"
chmod 700 "$DEST"
mkdir -p "${WORK}/data"
log "start → ${FINAL}"

# 1. Database. sqlite3's .backup makes a consistent copy even while Vaultwarden
#    is running (copying the file with cp could catch it mid-write).
sqlite3 "${SRC}/db.sqlite3" ".backup '${WORK}/data/db.sqlite3'"

# Check the copy isn't damaged.
CHECK="$(sqlite3 "${WORK}/data/db.sqlite3" 'PRAGMA integrity_check;')"
if [[ "$CHECK" != "ok" ]]; then
  log "integrity check failed on the copy: ${CHECK}; aborting"
  exit 1
fi

# 2. Everything else that matters (whatever exists).
for item in rsa_key.pem rsa_key.pub.pem rsa_key.der rsa_key.pub.der config.json attachments sends; do
  if [[ -e "${SRC}/${item}" ]]; then
    cp -a "${SRC}/${item}" "${WORK}/data/"
  fi
done

# 3. One archive (contents sit at the top level, ready to extract into $SRC).
tar -czf "${WORK}/vaultwarden.tar.gz" -C "${WORK}/data" .
rm -rf "${WORK}/data"

mv "$WORK" "$FINAL"
trap - EXIT

# Keep only the newest $KEEP.
ls -1dt "$DEST"/20*/ 2>/dev/null \
  | tail -n +$((KEEP + 1)) \
  | xargs -r rm -rf --

ITEMS="$(sqlite3 "${SRC}/db.sqlite3" 'SELECT COUNT(*) FROM ciphers;')"
log "ok $(du -h --apparent-size "${FINAL}/vaultwarden.tar.gz" | cut -f1), ${ITEMS} vault items — $(ls -1d "$DEST"/20*/ | wc -l)/${KEEP} kept"

if [[ -f "$HC_FILE" ]]; then
  curl -fsS -m 10 --retry 3 "$(cat "$HC_FILE")" >/dev/null || log "healthchecks ping failed"
fi
