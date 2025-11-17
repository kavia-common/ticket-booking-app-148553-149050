#!/usr/bin/env bash
# Ensure all Database startup scripts are executable in environments where
# git file modes are not preserved (e.g., certain CI/preview runners).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

chmod +x "${SCRIPT_DIR}/startup.sh" || true
chmod +x "${SCRIPT_DIR}/start-postgres.sh" || true
chmod +x "${SCRIPT_DIR}/run-postgres-docker.sh" || true
chmod +x "${SCRIPT_DIR}/backup_db.sh" || true
chmod +x "${SCRIPT_DIR}/restore_db.sh" || true

echo "Scripts marked executable."
