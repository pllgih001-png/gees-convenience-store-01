#!/usr/bin/env bash
# SCRATCH/TEST ONLY. Applies the versioned migrations in lexicographic order to
# the throwaway test database. Stops at the first failure (ON_ERROR_STOP=1).
# Never point this at a production database.
#
# Usage: su postgres -c "bash /workspace/scripts/test/01_apply_migrations.sh [dbname]"
set -euo pipefail

PGHOST="${PGHOST:-/tmp/geespg}"
PGPORT="${PGPORT:-5433}"
DB="${1:-gees_test}"
PSQL="/usr/lib/postgresql/16/bin/psql"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

shopt -s nullglob
for f in "$ROOT"/supabase/migrations/*.sql; do
  name="$(basename "$f")"
  if psql -h "$PGHOST" -p "$PGPORT" -d "$DB" -v ON_ERROR_STOP=1 -q -f "$f"; then
    echo "ok    $name"
  else
    echo "FAIL  $name"
    exit 1
  fi
done
echo "all migrations applied to $DB"
