#!/usr/bin/env bash
# BookStack backup: database dump + config/uploads folder, keeps the newest 7.
#
# Usage:  backup.sh
#
# Each run makes one folder:
#   /tank/backups/bookstack/2026-11-19_03-15-00/
#       db.sql.gz       full database dump (pages, books, users, settings)
#       config.tar.gz   /config folder (uploaded images and attachments, app settings)
#
# NOT in the backup: APP_KEY (lives in nas/bookstack/.env). Keep it in the
# password manager: without it, a restore can't decrypt sessions or MFA secrets.
#
# cron (crontab -e):
#   15 3 * * * /opt/stacks/nas/bookstack/backup.sh >> /home/mmoxey/bookstack-backup.log 2>&1

set -euo pipefail

DB_CONTAINER="bookstack-db"
DB_NAME="bookstack"
CONFIG_DIR="/opt/appdata/bookstack/config"
DEST="/tank/backups/bookstack"
KEEP=7
TS="$(date +%F_%H-%M-%S)"
WORK="${DEST}/.${TS}.part"          # hidden while in progress
FINAL="${DEST}/${TS}"

log() { echo "$(date '+%F %T') [bookstack] $*"; }

# Only one backup at a time.
exec 9>/tmp/bookstack-backup.lock
if ! flock -w 600 9; then
  log "another backup is still running after 10 min; skipping"
  exit 1
fi

# Database must be running.
if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
  log "container ${DB_CONTAINER} is not running; skipping"
  exit 1
fi

# If anything fails, remove the half-finished folder.
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK"
log "start → ${FINAL}"

# 1. Database. --single-transaction = a consistent snapshot without locking
#    the site. The password comes from the container's own environment, so it
#    never appears on the host's command line.
docker exec "$DB_CONTAINER" sh -c \
  'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb-dump -uroot \
     --single-transaction --routines --triggers --databases '"$DB_NAME" \
  | gzip > "${WORK}/db.sql.gz"

# Check the dump is complete: gzip is valid and the dump's last line says so.
gzip -t "${WORK}/db.sql.gz"
if ! zcat "${WORK}/db.sql.gz" | tail -n 1 | grep -q "Dump completed"; then
  log "database dump looks incomplete; aborting"
  exit 1
fi

# 2. Config + uploads (skip logs and cache; they rebuild themselves).
tar -czf "${WORK}/config.tar.gz" -C "$CONFIG_DIR" \
    --exclude=./log \
    --exclude=./logs \
    --exclude='./www/framework/cache' \
    .

# Only a finished backup gets its real name.
mv "$WORK" "$FINAL"
trap - EXIT

# Keep only the newest $KEEP backups (hidden .part folders are never counted).
ls -1dt "$DEST"/20*/ 2>/dev/null \
  | tail -n +$((KEEP + 1)) \
  | xargs -r rm -rf --

log "ok db $(du -h "${FINAL}/db.sql.gz" | cut -f1), files $(du -h "${FINAL}/config.tar.gz" | cut -f1) — $(ls -1d "$DEST"/20*/ | wc -l)/${KEEP} kept"

# Optional: ping healthchecks.io if ~/.bookstack-backup-hc exists (the URL is a secret).
HC_FILE="$HOME/.bookstack-backup-hc"
if [[ -f "$HC_FILE" ]]; then
  curl -fsS -m 10 --retry 3 "$(cat "$HC_FILE")" >/dev/null || log "healthchecks ping failed"
fi
