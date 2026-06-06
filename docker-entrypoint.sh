#!/bin/sh
set -eu

echo "[ENTRYPOINT] Waiting for MariaDB at ${DB_HOST:-db}:${DB_PORT:-3306}..."

until mariadb-admin ping \
  -h "${DB_HOST:-db}" \
  -P "${DB_PORT:-3306}" \
  -u"${DB_USER:-nroshield}" \
  -p"${DB_PASS:-}" \
  --silent; do
  sleep 2
done

echo "[ENTRYPOINT] MariaDB is ready. Running migrations..."
cd /app/backend
npm run migrate

echo "[ENTRYPOINT] Starting backend..."
exec node server.js
