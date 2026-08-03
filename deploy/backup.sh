#!/usr/bin/env bash
# Nightly SQLite backup with 14-day rotation. Uses sqlite3's online .backup so a
# live WAL database copies consistently. Optionally rclone the folder offsite.
set -euo pipefail
DB=/opt/pandanet/data/pandanet.db
OUT=/opt/pandanet/data/backups
mkdir -p "$OUT"
STAMP=$(date -u +%Y-%m-%d)
sqlite3 "$DB" ".backup '$OUT/pandanet-$STAMP.db'"
gzip -f "$OUT/pandanet-$STAMP.db"
# This cron runs as root, so every artifact it touches would otherwise be
# root-owned inside a directory the service account has to manage.
chown -R pandanet:pandanet "$OUT"
find "$OUT" -name 'pandanet-*.db.gz' -mtime +14 -delete
# Offsite (optional): rclone copy "$OUT" remote:pandanet-backups
