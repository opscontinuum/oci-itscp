#!/usr/bin/env bash
# dg-health.sh — Oracle Data Guard health snapshot for the three-member
# configuration in docs/01-architecture.md §3. Read-only.
set -uo pipefail
CONN="${DG_CONNECT:?set DG_CONNECT, e.g. sys/****@EBSPROD_IAD as sysdba}"

echo "=== Oracle Data Guard Broker configuration ==="
dgmgrl -silent "$CONN" "show configuration verbose"

echo
echo "=== Per-member lag and transport ==="
for DB in "${DG_PRIMARY:-EBSPROD_IAD}" "${DG_STANDBY_LOCAL:-EBSPROD_IAD2}" "${DG_STANDBY_REMOTE:-EBSPROD_PHX}"; do
  echo "--- $DB ---"
  dgmgrl -silent "$CONN" "show database '$DB'" 2>&1 | sed 's/^/  /'
done

echo
echo "=== Switchover readiness (validate) ==="
dgmgrl -silent "$CONN" "validate database '${DG_STANDBY_REMOTE:-EBSPROD_PHX}'"

echo
echo "=== Flashback Database status (required for reinstate + snapshot standby drills) ==="
sqlplus -s /nolog <<SQL
connect $CONN
SET HEADING ON PAGESIZE 50 LINESIZE 160
SELECT name, database_role, flashback_on, protection_mode, open_mode FROM v\$database;
SELECT name, value FROM v\$parameter WHERE name IN ('db_flashback_retention_target','log_archive_max_processes');
PROMPT === Fast Recovery Area (must have headroom for RB-04 snapshot standby drills) ===
SELECT name, ROUND(space_limit/1024/1024/1024,1) AS limit_gb,
       ROUND(space_used/1024/1024/1024,1) AS used_gb,
       ROUND(space_used/NULLIF(space_limit,0)*100,1) AS pct_used
  FROM v\$recovery_file_dest;
exit
SQL

echo
echo "NOTE: FLASHBACK_ON must be YES on all three members."
echo "      Without it: no reinstate after failover (RB-03), and no snapshot standby drills (RB-04)."
