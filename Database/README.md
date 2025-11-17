# Database Container

This directory provides scripts to run PostgreSQL reliably in the preview environment.

How to start in Preview (replaces any direct `postgres -c ...` invocation):
- Preferred single command:
  bash ./startup.sh
  - This will attempt to start a local PostgreSQL on port 5001 using system binaries.
  - If local binaries are not available, it falls back to Docker via run-postgres-docker.sh.
  - On success, it performs a pg_isready health check and exits with code 0.

Options:
1) Local binaries (preferred if PostgreSQL is available on the system)
   - Runs PostgreSQL on port 5001, initializes a data directory if missing, configures listen_addresses='*', creates the default DB/user, and performs a health check.
   - Command:
     bash start-postgres.sh

2) Docker fallback (if local postgres is not installed)
   - Requires Docker.
   - Command:
     bash run-postgres-docker.sh

Defaults (can be overridden with environment variables before running scripts):
- DB_NAME=myapp
- DB_USER=appuser
- DB_PASSWORD=dbuser123
- DB_PORT=5001
- PGDATA_DIR=/var/lib/postgresql/data

Artifacts:
- db_connection.txt -> psql connection helper
- db_visualizer/postgres.env -> env file for the simple database viewer

Health check:
- The startup script uses pg_isready and psql to verify the instance and exits with EXIT_CODE 0 on success.
- For CI/Preview, ensure your runner executes: bash Database/startup.sh
