#!/usr/bin/env bash
# Delegates to start-postgres.sh with the new defaults (port 5001) for compatibility
# Ensures the command terminates after readiness checks with exit code 0 on success.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export DB_PORT="${DB_PORT:-5001}"

# In some environments, executable bit may be lost; attempt to restore.
if [ ! -x "${SCRIPT_DIR}/start-postgres.sh" ] && [ -f "${SCRIPT_DIR}/start-postgres.sh" ]; then
  chmod +x "${SCRIPT_DIR}/start-postgres.sh" || true
fi

if [ -x "${SCRIPT_DIR}/start-postgres.sh" ]; then
  # start-postgres.sh already performs pg_isready and a psql sanity query and exits 0 on success.
  exec "${SCRIPT_DIR}/start-postgres.sh"
else
  echo "start-postgres.sh not found or not executable. Creating a hint:"
  echo "Please run: bash Database/start-postgres.sh"
  exit 1
fi
