#!/usr/bin/env bash
# Restore a PandaNet backup. Run as root:  bash restore.sh <backup.db.gz|backup.db>
#
# The -wal/-shm sidecar files MUST be removed. SQLite treats a leftover WAL as
# belonging to the database file it sits beside, so copying a backup over the DB
# without deleting them replays the OLD database's WAL onto the restored file —
# which yields corruption, not a rollback.
set -euo pipefail
SRC="${1:?usage: restore.sh <backup.db.gz|backup.db>}"
DB="${DB:-/opt/pandanet/data/pandanet.db}"
[ -f "$SRC" ] || { echo "no such backup: $SRC" >&2; exit 1; }

systemctl stop pandanet

# Keep the live database rather than clobbering it — a restore is not a delete.
if [ -f "$DB" ]; then
  KEEP="$DB.pre-restore.$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$DB" "$KEEP"
  echo "previous database kept at $KEEP"
fi
rm -f "$DB-wal" "$DB-shm"      # load-bearing: see the comment above

case "$SRC" in
  *.gz) gunzip -c "$SRC" > "$DB" ;;
  *)    cp "$SRC" "$DB" ;;
esac
chown pandanet:pandanet "$DB"
chmod 640 "$DB"

# Fail loudly BEFORE restarting if the restored file is not a healthy database.
sqlite3 "$DB" 'PRAGMA integrity_check;' | head -1

systemctl start pandanet
sleep 1
systemctl is-active --quiet pandanet && echo "restore complete; service is running"
