#!/usr/bin/env bash
# SCRATCH/TEST ONLY. Drops and recreates the throwaway test database, then
# applies the Supabase shim. Never point this at a production database.
#
# Usage: su postgres -c "bash /workspace/scripts/test/00_reset_db.sh [dbname]"
set -euo pipefail

PGHOST="${PGHOST:-/tmp/geespg}"
PGPORT="${PGPORT:-5433}"
DB="${1:-gees_test}"
PSQL="/usr/lib/postgresql/16/bin/psql"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

psql -h "$PGHOST" -p "$PGPORT" -d postgres -v ON_ERROR_STOP=1 -q \
  -c "drop database if exists $DB with (force);" \
  -c "create database $DB;"

psql -h "$PGHOST" -p "$PGPORT" -d "$DB" -v ON_ERROR_STOP=1 -q \
  -f "$ROOT/scripts/test/00_supabase_shim.sql"

echo "reset: $DB recreated with shim applied"
