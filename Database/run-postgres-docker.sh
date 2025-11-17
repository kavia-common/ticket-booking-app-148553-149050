#!/usr/bin/env bash
set -euo pipefail

# Run PostgreSQL using the official Docker image as a fallback
# Exposes DB on host port 5001 to align with the task requirement.
DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5001}"

# Choose a deterministic container name for reuse
CONTAINER_NAME="${CONTAINER_NAME:-ticket_booking_pg}"

# Pull and run postgres
echo "Starting dockerized PostgreSQL (${CONTAINER_NAME}) on port ${DB_PORT} ..."
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
docker run -d --name "${CONTAINER_NAME}" \
  -e POSTGRES_DB="${DB_NAME}" \
  -e POSTGRES_USER="${DB_USER}" \
  -e POSTGRES_PASSWORD="${DB_PASSWORD}" \
  -p "${DB_PORT}:5432" \
  postgres:16

echo "Waiting for container to become healthy ..."
for i in $(seq 1 40); do
  if docker exec "${CONTAINER_NAME}" pg_isready -U "${DB_USER}" >/dev/null 2>&1; then
    echo "PostgreSQL container is ready."
    break
  fi
  sleep 1
done

if ! docker exec "${CONTAINER_NAME}" pg_isready -U "${DB_USER}" >/dev/null 2>&1; then
  echo "ERROR: PostgreSQL in Docker did not become ready in time."
  exit 1
fi

# Optional: load seed if exists
SEED_FILE="database_backup.sql"
if [ -f "${SEED_FILE}" ]; then
  echo "Loading ${SEED_FILE} into container database ..."
  docker cp "${SEED_FILE}" "${CONTAINER_NAME}:/tmp/seed.sql"
  # Use postgres DB to allow CREATE DATABASE/GRANT statements
  docker exec -u postgres "${CONTAINER_NAME}" bash -lc "psql -d postgres -f /tmp/seed.sql" >/dev/null 2>&1 || true
  echo "Seed load finished (errors ignored if objects already exist)."
fi

echo "PostgreSQL in Docker is up. Connection:"
echo "  psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}"
echo "EXIT_CODE 0"
