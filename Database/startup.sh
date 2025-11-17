#!/usr/bin/env bash
# Delegates to start-postgres.sh with the new defaults (port 5001) for compatibility
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export DB_PORT="${DB_PORT:-5001}"

if [ -x "${SCRIPT_DIR}/start-postgres.sh" ]; then
  exec "${SCRIPT_DIR}/start-postgres.sh"
else
  echo "start-postgres.sh not found or not executable. Creating a hint:"
  echo "Please run: bash Database/start-postgres.sh"
  exit 1
fi
