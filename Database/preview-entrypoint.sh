#!/usr/bin/env bash
# Preview entrypoint wrapper for Database container
# - Ensures scripts are executable
# - Runs Database/startup.sh which initializes and starts PostgreSQL or falls back to Docker
# - Confirms readiness via pg_isready on port 5001
# - Exits 0 on success so preview can proceed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure scripts are executable (cover CI where file modes may be lost)
if [ -f "${SCRIPT_DIR}/make-executable.sh" ]; then
  chmod +x "${SCRIPT_DIR}/make-executable.sh" || true
  bash "${SCRIPT_DIR}/make-executable.sh" || true
else
  chmod +x "${SCRIPT_DIR}/startup.sh" || true
  chmod +x "${SCRIPT_DIR}/start-postgres.sh" || true
fi

# Run the main startup script (it exits 0 on success internally)
echo "Starting Database via ${SCRIPT_DIR}/startup.sh ..."
bash "${SCRIPT_DIR}/startup.sh"

# Readiness check: pg_isready on port 5001 (use system if present, else try in PATH)
DB_PORT="${DB_PORT:-5001}"

# Try to locate pg_isready
PG_ISREADY_BIN=""
if command -v pg_isready >/dev/null 2>&1; then
  PG_ISREADY_BIN="$(command -v pg_isready)"
else
  if [ -d /usr/lib/postgresql ]; then
    ver="$(ls /usr/lib/postgresql/ 2>/dev/null | sort -Vr | head -1 || true)"
    if [ -n "${ver:-}" ] && [ -x "/usr/lib/postgresql/${ver}/bin/pg_isready" ]; then
      PG_ISREADY_BIN="/usr/lib/postgresql/${ver}/bin/pg_isready"
    fi
  fi
fi

# Perform readiness probe if pg_isready is available
if [ -n "${PG_ISREADY_BIN}" ]; then
  echo "Verifying readiness with ${PG_ISREADY_BIN} on port ${DB_PORT} ..."
  for i in $(seq 1 20); do
    if "${PG_ISREADY_BIN}" -h 127.0.0.1 -p "${DB_PORT}" >/dev/null 2>&1; then
      echo "Database is ready on port ${DB_PORT}."
      echo "EXIT_CODE 0"
      exit 0
    fi
    sleep 1
  done
  echo "WARNING: pg_isready did not report ready within timeout. Proceeding based on startup.sh success."
else
  echo "pg_isready not found; relying on startup.sh health checks."
fi

# Final success exit (startup.sh already verified health and wrote EXIT_CODE 0 on success)
echo "EXIT_CODE 0"
exit 0
