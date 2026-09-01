#!/usr/bin/env bash
#
# capture-lag-snapshot.sh — forensic capture of Oracle Data Guard transport and
# apply lag at the moment of loss. Part of RB-02 §1 ("capture forensics first").
#
# GOVERNING RULE: this script is READ-ONLY and must stay that way. It runs
# BEFORE any role transition, because the numbers it captures are gone the
# moment FAILOVER completes. Its output is the data-loss statement Finance will
# require (RB-02 §6), so it prefers partial evidence over no evidence: every
# probe is best-effort and a failed probe is recorded, not fatal.
#
# It connects to the STANDBY side by preference. In a regional loss the primary
# is unreachable, and the standby's own view of the lag is the truth anyway.
#
# Requires: dgmgrl and/or sqlplus on PATH (run from a DB node or a host with the
# Oracle client). Falls back gracefully when one is missing.
#
set -uo pipefail

CONFIG="${DR_CONFIG:-$(dirname "$0")/../../terraform/dr-resources.env}"
EVIDENCE_DIR="${DR_EVIDENCE_DIR:-$(dirname "$0")/../../evidence}"
OUT=""
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: capture-lag-snapshot.sh [--out <file>] [--dry-run]

  --out       Evidence file to write. Default: evidence/lag-snapshot-<UTC>.md
  --dry-run   Print the probes without executing them.

No arguments are required. Run it FIRST in RB-02, before any FAILOVER.

Refused by design:
  This script never issues a DDL, DML, or Broker command that changes state.
  If you need to fail over, that is RB-02 §3 -- after this has run.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)     OUT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# shellcheck source=/dev/null
[[ -f "$CONFIG" ]] && source "$CONFIG"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="${OUT:-${EVIDENCE_DIR}/lag-snapshot-${STAMP}.md}"

PRIMARY="${DG_PRIMARY:-EBSPROD_IAD}"
LOCAL_SB="${DG_STANDBY_LOCAL:-EBSPROD_IAD2}"
REMOTE_SB="${DG_STANDBY_REMOTE:-EBSPROD_PHX}"

# Connect strings. DG_CONNECT_STANDBY is preferred: in a regional loss the
# primary connect string (DG_CONNECT) will hang until TCP timeout.
CONN_SB="${DG_CONNECT_STANDBY:-${DG_CONNECT:-}}"
CONN_PRI="${DG_CONNECT:-}"

# --- guard rails ------------------------------------------------------------

assert_read_only() {
  # Defensive: fail loudly if someone wires a state-changing verb into this file.
  # Looks for Broker verbs passed to dgmgrl and for state-changing SQL at the start of a
  # line, so that prose in usage text does not trip it.
  if grep -qiE '(dgmgrl[^#]*"[[:space:]]*(failover|switchover|reinstate|convert |edit |enable |disable |remove |add )|^[[:space:]]*(alter (database|system)|shutdown|startup)\b)' "$0"; then
    echo "REFUSED: capture-lag-snapshot.sh must remain read-only. A state-changing verb was found in the script body." >&2
    exit 3
  fi
}

# --- probes (all best-effort) -----------------------------------------------

probe() {
  # probe <label> <command...>  -> appends a fenced block to the report
  local label="$1"; shift
  {
    echo
    echo "### $label"
    echo
    echo '```'
  } >> "$OUT"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*" | tee -a "$OUT"
  else
    echo "-> $label"
    # 60 s cap per probe: a hung primary must not stall the whole capture.
    if ! timeout 60 "$@" >> "$OUT" 2>&1; then
      echo "(probe failed or timed out after 60 s -- recorded as evidence of unreachability)" >> "$OUT"
    fi
  fi
  echo '```' >> "$OUT"
}

sql_probe() {
  # sql_probe <label> <connect-string> <sql>
  local label="$1" conn="$2" sql="$3"
  [[ -z "$conn" ]] && { echo "-> $label: skipped (no connect string)"; return; }
  probe "$label" bash -c "sqlplus -s /nolog <<'SQL'
connect $conn
SET HEADING ON PAGESIZE 100 LINESIZE 200 FEEDBACK OFF
ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24:MI:SS TZR';
$sql
exit
SQL"
}

# --- main -------------------------------------------------------------------

assert_read_only

if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$(dirname "$OUT")"
  cat > "$OUT" <<HDR
# Data Guard lag snapshot — ${TS}

**Purpose:** forensic capture at the moment of loss (RB-02 §1). Feeds the data-loss
statement in RB-02 §6. Captured by \`${USER:-unknown}\` on \`$(hostname)\`.

| Member | Role in design |
|---|---|
| \`${PRIMARY}\` | Primary (Ashburn AD-1) |
| \`${LOCAL_SB}\` | SYNC standby (Ashburn AD-2) |
| \`${REMOTE_SB}\` | ASYNC standby (Phoenix) |

> Every probe below is best-effort. A block that reads "probe failed or timed out" is
> itself evidence: it records which members were unreachable at ${TS}.
HDR
else
  OUT=/dev/stdout
fi

if command -v dgmgrl >/dev/null 2>&1 && [[ -n "$CONN_SB" ]]; then
  probe "Broker configuration (from standby side)" dgmgrl -silent "$CONN_SB" "show configuration verbose"
  for DB in "$REMOTE_SB" "$LOCAL_SB" "$PRIMARY"; do
    probe "Broker view of $DB (transport + apply lag)" dgmgrl -silent "$CONN_SB" "show database '$DB'"
  done
  probe "Failover readiness of $REMOTE_SB" dgmgrl -silent "$CONN_SB" "validate database '$REMOTE_SB'"
else
  echo "-> dgmgrl not available or DG_CONNECT/DG_CONNECT_STANDBY unset: Broker probes skipped" | tee -a "$OUT"
fi

if command -v sqlplus >/dev/null 2>&1; then
  sql_probe "v\$dataguard_stats on the standby (authoritative lag at capture time)" "$CONN_SB" \
    "SELECT name, value, time_computed, datum_time FROM v\$dataguard_stats WHERE name IN ('transport lag','apply lag','apply finish time','estimated startup time') ORDER BY name;"
  sql_probe "Last received and last applied redo on the standby" "$CONN_SB" \
    "SELECT thread#, MAX(sequence#) AS last_received FROM v\$archived_log WHERE registrar='RFS' GROUP BY thread# ORDER BY thread#;
SELECT thread#, MAX(sequence#) AS last_applied FROM v\$archived_log WHERE applied='YES' GROUP BY thread# ORDER BY thread#;
SELECT process, status, thread#, sequence#, block# FROM v\$managed_standby WHERE process LIKE 'MRP%' OR process LIKE 'RFS%' ORDER BY process;"
  sql_probe "Standby database role, SCN and open mode" "$CONN_SB" \
    "SELECT name, database_role, open_mode, protection_mode, flashback_on, current_scn, SCN_TO_TIMESTAMP(current_scn) AS scn_time FROM v\$database;"
  sql_probe "Primary current SCN (will fail if the primary is lost -- that is expected)" "$CONN_PRI" \
    "SELECT name, database_role, current_scn, SCN_TO_TIMESTAMP(current_scn) AS scn_time, SYSTIMESTAMP FROM v\$database;"
else
  echo "-> sqlplus not on PATH: v\$dataguard_stats probes skipped" | tee -a "$OUT"
fi

if [[ $DRY_RUN -eq 0 ]]; then
  cat >> "$OUT" <<'FTR'

## Data-loss statement (complete by hand before RB-02 §6)

| Field | Value |
|---|---|
| Time of loss (UTC) | |
| Last redo applied on the surviving standby (SCN / timestamp) | |
| Transport lag at capture | |
| Apply lag at capture | |
| Estimated committed transactions at risk | |
| Tier-0 RPO target (`docs/02-mtd-tiers.md` §2) | < 30 s cross-region |
| Within RPO? | ☐ yes ☐ **no → RB-02 §7d applies: Concurrent Managers stay down** |

Signed (DR Commander): __________  Reviewed (Finance): __________
FTR
  echo "=== Snapshot written to $OUT ==="
  echo "NEXT: ./scripts/oci/capture-replication-state.sh   (storage-tier replica timestamps)"
fi
