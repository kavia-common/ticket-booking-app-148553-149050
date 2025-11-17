# Database Preview Entrypoint

Preview runners should execute:
  bash Database/preview-entrypoint.sh

This wrapper:
- Ensures startup scripts are executable (for CI runners that lose file modes)
- Invokes Database/startup.sh which initializes and starts PostgreSQL on port 5001 (or falls back to Docker)
- Validates readiness with pg_isready on 127.0.0.1:5001 when available
- Exits with code 0 on success

Notes:
- For direct/manual execution you can still run: bash Database/startup.sh
- Connection helper is written to Database/db_connection.txt
- Database viewer environment is written to Database/db_visualizer/postgres.env
