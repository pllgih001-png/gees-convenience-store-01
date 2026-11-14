#!/usr/bin/env bash
# SCRATCH/TEST ONLY — A4-1 concurrency regression.
# Proves that under genuinely concurrent checkouts the aggregate per-product
# availability check (plus SELECT ... FOR UPDATE row locks) never over-reserves:
# exactly ONE of N competing requests wins the last units of a product, and the
# rest fail with insufficient_stock. Includes a duplicate-line basket (the same
# product on two lines) so a per-line check alone could not pass this.
# Never point this at a production database.
#
# Usage: PGUSER=postgres bash /workspace/scripts/test/05_stock_concurrency.sh
set -euo pipefail

PGHOST="${PGHOST:-/tmp/geespg}"
PGPORT="${PGPORT:-5433}"
DB="${DB:-gees_test}"
PGUSER="${PGUSER:-postgres}"
export PGUSER
PSQL="/usr/lib/postgresql/16/bin/psql"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
N=10

bash "$ROOT/scripts/test/00_reset_db.sh" >/dev/null
bash "$ROOT/scripts/test/01_apply_migrations.sh" >/dev/null

PID="$("$PSQL" -h "$PGHOST" -p "$PGPORT" -d "$DB" -tA \
  -c "select id from public.products where visible order by sort_order, name offset 24 limit 1")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/call.sql" <<'SQL'
\set ON_ERROR_STOP on
set role service_role;
set request.jwt.claims = '{"role":"service_role"}';
select 'OK' from public.create_order(:'payload'::jsonb, :'key'::uuid, :'owner', null);
SQL

fail=0

scenario() {
  local stock="$1" items="$2" expected_ok="$3" label="$4"
  "$PSQL" -h "$PGHOST" -p "$PGPORT" -d "$DB" -q \
    -c "delete from public.stock_reservations;" \
    -c "update public.products set stock = ${stock} where id = '${PID}';"

  local i key
  for i in $(seq 1 "$N"); do
    key="$(printf 'c0000000-0000-0000-0000-%012d' "$i")"
    (
      "$PSQL" -h "$PGHOST" -p "$PGPORT" -d "$DB" -tA \
        -v payload="$items" -v key="$key" -v owner="g:conc$i" \
        -f "$TMP/call.sql" > "$TMP/$i.out" 2> "$TMP/$i.err" || true
    ) &
  done
  wait || true

  local ok held
  ok="$(grep -l '^OK' "$TMP"/*.out 2>/dev/null | wc -l | tr -d ' ')"
  held="$("$PSQL" -h "$PGHOST" -p "$PGPORT" -d "$DB" -tA \
    -c "select coalesce(sum(quantity),0) from public.stock_reservations where product_id='${PID}' and status='held';")"

  if [ "$ok" = "$expected_ok" ] && [ "$held" -le "$stock" ]; then
    echo "PASS  ${label}  (ok=${ok} expected=${expected_ok} held=${held} stock=${stock})"
  else
    echo "FAIL  ${label}  (ok=${ok} expected=${expected_ok} held=${held} stock=${stock})"
    fail=1
  fi
  rm -f "$TMP"/*.out "$TMP"/*.err
}

scenario 1 "{\"items\":[{\"product_id\":\"${PID}\",\"quantity\":1}]}" 1 \
  "A single-unit race (stock 1, 10 x qty 1)"

scenario 2 "{\"items\":[{\"product_id\":\"${PID}\",\"quantity\":1},{\"product_id\":\"${PID}\",\"quantity\":1}]}" 1 \
  "B duplicate-line race (stock 2, 10 x [1+1])"

echo
if [ "$fail" -eq 0 ]; then
  echo "stock concurrency: ALL PASS"
else
  echo "stock concurrency: FAILURES PRESENT"
  exit 1
fi
