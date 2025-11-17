#!/usr/bin/env bash
set -euo pipefail

# Robust PostgreSQL startup script
# - Initializes a data directory if missing
# - Configures to listen on all addresses and port 5001
# - Starts the server and performs health checks
# - Imports a default schema if provided

DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5001}"        # per task requirement
PGDATA_DIR="${PGDATA_DIR:-/var/lib/postgresql/data}"
PGLOG_DIR="${PGLOG_DIR:-/var/lib/postgresql/logs}"
PGCONF_EXTRA="${PGCONF_EXTRA:-}"   # optional extra config line(s)

# Try to detect system postgres installation path
detect_pg_bin() {
  # Prefer /usr/lib/postgresql/<version>/bin on Debian/Ubuntu
  if [ -d /usr/lib/postgresql ]; then
    local ver
    ver="$(ls /usr/lib/postgresql/ 2>/dev/null | sort -Vr | head -1 || true)"
    if [ -n "${ver:-}" ] && [ -d "/usr/lib/postgresql/${ver}/bin" ]; then
      echo "/usr/lib/postgresql/${ver}/bin"
      return 0
    fi
  fi
  # Fallbacks in PATH (if present)
  if command -v postgres >/dev/null 2>&1; then
    # Derive based on the postgres binary location
    local bin
    bin="$(dirname "$(command -v postgres)")"
    echo "$bin"
    return 0
  fi
  echo ""
  return 1
}

PG_BIN="$(detect_pg_bin || true)"

if [ -z "${PG_BIN}" ]; then
  echo "ERROR: Could not find PostgreSQL binaries (postgres, initdb, pg_ctl, pg_isready)."
  echo "Hint: This environment may not have PostgreSQL installed. You can run via Docker using:"
  echo "  ./run-postgres-docker.sh"
  exit 1
fi

PG_CTL="${PG_BIN}/pg_ctl"
INITDB="${PG_BIN}/initdb"
POSTGRES="${PG_BIN}/postgres"
PSQL="${PG_BIN}/psql"
PG_ISREADY="${PG_BIN}/pg_isready"
CREATEUSER="${PG_BIN}/createuser"
CREATEDB="${PG_BIN}/createdb"
PG_DUMP="${PG_BIN}/pg_dump"

# Ensure directories
sudo mkdir -p "${PGDATA_DIR}" "${PGLOG_DIR}" >/dev/null 2>&1 || true
sudo chown -R postgres:postgres "$(dirname "${PGDATA_DIR}")" >/dev/null 2>&1 || true
sudo chown -R postgres:postgres "${PGDATA_DIR}" "${PGLOG_DIR}" >/dev/null 2>&1 || true

# Initialize database cluster if needed
if [ ! -f "${PGDATA_DIR}/PG_VERSION" ]; then
  echo "Initializing PostgreSQL data directory at ${PGDATA_DIR} ..."
  sudo -u postgres "${INITDB}" -D "${PGDATA_DIR}"
fi

# Update postgresql.conf for listen addresses and port
PGCONF="${PGDATA_DIR}/postgresql.conf"
if ! grep -q "^port *= *${DB_PORT}" "${PGCONF}" 2>/dev/null; then
  echo "Configuring PostgreSQL port=${DB_PORT} and listen_addresses='*' ..."
  sudo -u postgres bash -c "echo \"# Added by start-postgres.sh\" >> '${PGCONF}'"
  sudo -u postgres bash -c "echo \"port = ${DB_PORT}\" >> '${PGCONF}'"
  sudo -u postgres bash -c "echo \"listen_addresses = '*'\" >> '${PGCONF}'"
  if [ -n "${PGCONF_EXTRA}" ]; then
    sudo -u postgres bash -c "echo \"${PGCONF_EXTRA}\" >> '${PGCONF}'"
  fi
fi

# Configure pg_hba.conf to allow local connections and password auth
PGHBA="${PGDATA_DIR}/pg_hba.conf"
# Ensure at least md5 or scram auth for local connections
if ! grep -q "^host *all *all *0.0.0.0/0 *md5" "${PGHBA}" 2>/dev/null && ! grep -q "^host *all *all *0.0.0.0/0 *scram-sha-256" "${PGHBA}" 2>/dev/null; then
  echo "Configuring pg_hba.conf to allow remote connections with password ..."
  sudo -u postgres bash -c "echo \"# Added by start-postgres.sh\" >> '${PGHBA}'"
  sudo -u postgres bash -c "echo \"host    all             all             0.0.0.0/0               md5\" >> '${PGHBA}'"
  sudo -u postgres bash -c "echo \"host    all             all             ::/0                    md5\" >> '${PGHBA}'"
fi

# Start PostgreSQL (if not already running)
if ! sudo -u postgres "${PG_ISREADY}" -p "${DB_PORT}" >/dev/null 2>&1; then
  echo "Starting PostgreSQL server ..."
  # Try pg_ctl for controlled startup
  sudo -u postgres "${PG_CTL}" -D "${PGDATA_DIR}" -l "${PGLOG_DIR}/postgresql.log" start

  # Wait for readiness
  echo "Waiting for PostgreSQL to become ready on port ${DB_PORT} ..."
  for i in $(seq 1 30); do
    if sudo -u postgres "${PG_ISREADY}" -p "${DB_PORT}" >/dev/null 2>&1; then
      echo "PostgreSQL is ready."
      break
    fi
    sleep 1
  done
  if ! sudo -u postgres "${PG_ISREADY}" -p "${DB_PORT}" >/dev/null 2>&1; then
    echo "ERROR: PostgreSQL did not become ready in time. Check logs at ${PGLOG_DIR}/postgresql.log"
    exit 1
  fi
else
  echo "PostgreSQL already running."
fi

# Create application role/user if needed
echo "Ensuring role '${DB_USER}' exists ..."
sudo -u postgres "${PSQL}" -p "${DB_PORT}" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
  sudo -u postgres "${PSQL}" -p "${DB_PORT}" -d postgres -c "CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';"

# Create database if needed
echo "Ensuring database '${DB_NAME}' exists ..."
sudo -u postgres "${PSQL}" -p "${DB_PORT}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
  sudo -u postgres "${CREATEDB}" -p "${DB_PORT}" -O "${DB_USER}" "${DB_NAME}"

# Grant privileges and ensure schema access for the user
sudo -u postgres "${PSQL}" -p "${DB_PORT}" -d postgres >/dev/null <<SQL
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
\c ${DB_NAME}
GRANT USAGE, CREATE ON SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
SQL

# Optional: if there is a seed SQL file, load it (idempotent where possible)
SEED_FILE_RELATIVE="database_backup.sql"
SEED_FILE_PATH="$(cd "$(dirname "$0")" && pwd)/${SEED_FILE_RELATIVE}"
if [ -f "${SEED_FILE_PATH}" ]; then
  echo "Found seed SQL file: ${SEED_FILE_RELATIVE}. Attempting to load into database '${DB_NAME}' ..."
  # Load using postgres DB to allow CREATE DATABASE commands within dump if any
  # Errors during CREATE statements for existing DB will be ignored
  sudo -u postgres "${PSQL}" -p "${DB_PORT}" -d postgres < "${SEED_FILE_PATH}" >/dev/null 2>&1 || true
  echo "Seed import step completed (errors ignored if objects already exist)."
fi

# Write connection helper files used by other tools in this workspace
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > "$(cd "$(dirname "$0")" && pwd)/db_connection.txt"

# Update db_visualizer.env for the Node viewer
DV_DIR="$(cd "$(dirname "$0")" && pwd)/db_visualizer"
mkdir -p "${DV_DIR}"
cat > "${DV_DIR}/postgres.env" <<ENVVARS
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
ENVVARS

# Health check
echo "Running health check ..."
if ! "${PG_ISREADY}" -h "127.0.0.1" -p "${DB_PORT}" >/dev/null 2>&1; then
  echo "ERROR: pg_isready failed."
  exit 1
fi

# Try a psql round-trip
if ! "${PSQL}" -h "127.0.0.1" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1; then
  echo "ERROR: psql connection as ${DB_USER} to ${DB_NAME} failed."
  echo "Try: PGPASSWORD='${DB_PASSWORD}' psql -h 127.0.0.1 -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME}"
  exit 1
fi

echo "PostgreSQL is up and healthy on port ${DB_PORT}."
echo "Connection string saved to db_connection.txt"
echo "EXIT_CODE 0"
exit 0
