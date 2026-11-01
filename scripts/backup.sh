#!/bin/sh
# Back up everything needed to restore Mini-Instinct, into ./backup/<date>/
#   - Supabase schema "app" (pg_dump via a Postgres 17 container, so nothing to install)
#   - Docker volumes: secrets (encrypted; useless without MASTER_KEY: keep that in your password manager)
#     and temporal-data (workflow state + your scheduled tasks). The browser profile is skipped (just log in again).
# Usage (Git Bash or WSL, from the project folder):  sh scripts/backup.sh
set -e
umask 077  # backups hold your messages and email content: readable by you only
cd "$(dirname "$0")/.."
DATABASE_URL=$(grep -E '^DATABASE_URL=' .env | cut -d= -f2-)
[ -n "$DATABASE_URL" ] || { echo "DATABASE_URL missing in .env"; exit 1; }
DEST="backup/$(date +%Y%m%d-%H%M)"
mkdir -p "$DEST"
export MSYS_NO_PATHCONV=1  # Git Bash: don't rewrite container paths

echo "1/3 Supabase schema app..."
# DB=... before docker (not -e "DB=$URL"): keeps the password out of the process list
DB="$DATABASE_URL" docker run --rm -e DB postgres:17-alpine sh -c 'pg_dump --schema=app --no-owner "$DB"' | gzip > "$DEST/app.sql.gz"
# pg_dump writes this footer last, so it only appears at the end of a dump that finished
gunzip -c "$DEST/app.sql.gz" | tail -n 5 | grep -q 'PostgreSQL database dump complete' || { echo "pg_dump failed: $DEST/app.sql.gz is incomplete"; exit 1; }

for vol in secrets temporal-data; do
  echo "volume $vol..."
  # streamed out and written here, so the file is yours and private (umask) even where Docker runs as root
  docker run --rm -v "extinct_$vol:/v:ro" alpine tar czf - -C /v . > "$DEST/$vol.tgz"
done
echo "Done: $DEST"
echo "Restore: gunzip -c $DEST/app.sql.gz | psql \"\$DATABASE_URL\"  ·  volumes: tar xzf into a fresh volume (see README)."
