#!/usr/bin/env bash
# SCRATCH/TEST ONLY — A8-2 rollback bookkeeping drill.
# Demonstrates, on a throwaway database, that a RAW-SQL rollback does NOT update
# the Supabase CLI's migration-history table (supabase_migrations.schema_migrations),
# and verifies the documented reconciliation procedure (see docs §21). The CLI
# history is SIMULATED here — no `supabase` CLI, no db push, no production access.
# Never point this at a production database.
#
# Usage: PGUSER=postgres bash /workspace/scripts/test/06_rollback_bookkeeping.sh
set -euo pipefail

PGHOST="${PGHOST:-/tmp/geespg}"
PGPORT="${PGPORT:-5433}"
DB="${DB:-gees_test}"
PGUSER="${PGUSER:-postgres}"
export PGUSER
PSQL="/usr/lib/postgresql/16/bin/psql"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

q() { "$PSQL" -h "$PGHOST" -p "$PGPORT" -d "$DB" -tA -c "$1"; }
qexec() { "$PSQL" -h "$PGHOST" -p "$PGPORT" -d "$DB" -q -c "$1"; }
public_tables() {
  q "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind = 'r'"
}
record_history() {
  for f in "$ROOT"/supabase/migrations/*.sql; do
    local name version
    name="$(basename "$f" .sql)"
    version="${name%%_*}"
    qexec "insert into supabase_migrations.schema_migrations(version, name)
           values ('$version', '$name') on conflict (version) do nothing;"
  done
}
hist_count() { q "select count(*) from supabase_migrations.schema_migrations"; }

fail=0
check() { # name actual expected
  if [ "$2" = "$3" ]; then echo "PASS  $1 (=$2)"; else echo "FAIL  $1 (got $2, expected $3)"; fail=1; fi
}

# 1. Fresh schema, then simulate the CLI recording all applied versions.
bash "$ROOT/scripts/test/00_reset_db.sh" >/dev/null
bash "$ROOT/scripts/test/01_apply_migrations.sh" >/dev/null
qexec "create schema if not exists supabase_migrations;
       create table if not exists supabase_migrations.schema_migrations
         (version text primary key, name text);"
record_history
check "1 applied public tables" "$(public_tables)" "11"
check "1 recorded history versions" "$(hist_count)" "13"

# 2. Raw-SQL rollback: schema empties, but the CLI history is untouched.
bash "$ROOT/scripts/test/02_rollback_migrations.sh" >/dev/null
check "2 public tables after raw rollback" "$(public_tables)" "0"
check "2 history still claims all applied (divergence)" "$(hist_count)" "13"

# 3. Reconciliation (as documented): clear/adjust the bookkeeping only.
qexec "delete from supabase_migrations.schema_migrations;"
check "3 history after reconciliation" "$(hist_count)" "0"
check "3 reconciliation did not change the schema" "$(public_tables)" "0"

# 4. Re-apply + re-record → schema and history realign.
bash "$ROOT/scripts/test/01_apply_migrations.sh" >/dev/null
record_history
check "4 re-applied public tables" "$(public_tables)" "11"
check "4 re-recorded history versions" "$(hist_count)" "13"

echo
if [ "$fail" -eq 0 ]; then
  echo "rollback bookkeeping: ALL PASS"
else
  echo "rollback bookkeeping: FAILURES PRESENT"
  exit 1
fi
