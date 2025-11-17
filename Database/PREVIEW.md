# Database Preview Startup

To start PostgreSQL in preview environments, do NOT call `postgres -c ...` directly.
Instead, run:

bash ./Database/startup.sh

Behavior:
- Uses local PostgreSQL binaries if available to launch on port 5001.
- Falls back to Docker (postgres:16) if local binaries are not present.
- Performs readiness checks using `pg_isready` and `psql`.
- Exits with code 0 on success to allow the preview to proceed.

Connection:
- psql connection helper is written to Database/db_connection.txt
- Database viewer env is written to Database/db_visualizer/postgres.env
