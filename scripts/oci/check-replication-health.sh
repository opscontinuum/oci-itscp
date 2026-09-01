#!/usr/bin/env bash
#
# check-replication-health.sh — single-pass health check across every replication
# mechanism in docs/03-replication-matrix.md. Safe: read-only.
#
# Exit codes: 0 = all green, 1 = warnings, 2 = critical, 3 = config/tooling error.
# Intended for both interactive use and cron (feeds docs/04-monitoring.md §3).
#
set -uo pipefail

# Takes no arguments: regions and resource OCIDs come from the resource config.
if [[ $# -gt 0 ]]; then
  case "$1" in
    -h|--help) echo "Usage: check-replication-health.sh   (no arguments; config from DR_CONFIG or terraform/dr-resources.env)"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1. This script takes no arguments; set regions in the config." >&2; exit 3 ;;
  esac
fi

CONFIG="${DR_CONFIG:-$(dirname "$0")/../../terraform/dr-resources.env}"
[[ -f "$CONFIG" ]] || { echo "ERROR: config not found: $CONFIG" >&2; exit 3; }
# shellcheck source=/dev/null
source "$CONFIG"

WARN=0; CRIT=0
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; WARN=1; }
crit() { printf '  \033[31mCRIT\033[0m  %s\n' "$*"; CRIT=1; }

echo "=== DR replication health · $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# --- R1: Oracle Data Guard --------------------------------------------------
echo
echo "[R1] Oracle Data Guard / Active Data Guard"
if command -v dgmgrl >/dev/null 2>&1; then
  DG_OUT=$(dgmgrl -silent "${DG_CONNECT:?set DG_CONNECT in config}" "show configuration" 2>&1)
  echo "$DG_OUT" | grep -qi "SUCCESS" && ok "Broker configuration: SUCCESS" \
    || crit "Broker configuration not SUCCESS -- $(echo "$DG_OUT" | tail -3 | tr '\n' ' ')"

  for DB in "${DG_STANDBY_LOCAL:-}" "${DG_STANDBY_REMOTE:-}"; do
    [[ -z "$DB" ]] && continue
    LAG=$(dgmgrl -silent "$DG_CONNECT" "show database '$DB' 'ApplyLag'" 2>/dev/null \
          | grep -oE '[0-9]+ (second|minute|hour)' | head -1)
    SECS=$(echo "$LAG" | awk '{n=$1; u=$2; if(u ~ /minute/) n*=60; if(u ~ /hour/) n*=3600; print n+0}')
    if   [[ -z "$LAG" ]];        then warn "$DB: apply lag not readable"
    elif [[ "$SECS" -gt 900 ]];  then crit "$DB: apply lag ${LAG} (>15 min)"
    elif [[ "$SECS" -gt 300 ]];  then warn "$DB: apply lag ${LAG} (>5 min)"
    else                              ok  "$DB: apply lag ${LAG}"
    fi
  done
else
  warn "dgmgrl not on PATH -- Data Guard checks skipped (run from a DB node)"
fi

# --- R3: OCI Block Volume — Volume Group Replication ------------------------
echo
echo "[R3] OCI Block Volume - Volume Group Replication"
for VGR in ${DR_VOLUME_GROUP_REPLICA_OCIDS:-}; do
  JSON=$(oci bv volume-group-replica get --volume-group-replica-id "$VGR" \
           --region "$DR_REGION" 2>/dev/null)
  if [[ -z "$JSON" ]]; then crit "$VGR: not readable"; continue; fi
  STATE=$(echo "$JSON" | jq -r '.data."lifecycle-state"')
  SYNCED=$(echo "$JSON" | jq -r '.data."time-last-synced" // empty')
  [[ "$STATE" == "AVAILABLE" ]] || crit "$VGR: state $STATE"
  if [[ -n "$SYNCED" ]]; then
    AGE=$(( $(date -u +%s) - $(date -u -d "$SYNCED" +%s) ))
    if   [[ $AGE -gt 7200 ]]; then crit "$VGR: last sync $((AGE/60)) min ago (>2 h)"
    elif [[ $AGE -gt 1800 ]]; then warn "$VGR: last sync $((AGE/60)) min ago (>30 min)"
    else                           ok  "$VGR: last sync $((AGE/60)) min ago"
    fi
  else
    warn "$VGR: no sync timestamp -- baseline may still be running"
  fi
done

# --- R5: OCI File Storage — File System Replication -------------------------
echo
echo "[R5] OCI File Storage - File System Replication"
for REP in ${DR_FSS_REPLICATION_OCIDS:-}; do
  JSON=$(oci fs replication get --replication-id "$REP" --region "$DR_REGION" 2>/dev/null)
  if [[ -z "$JSON" ]]; then crit "$REP: not readable"; continue; fi
  STATE=$(echo "$JSON" | jq -r '.data."lifecycle-state"')
  DELTA=$(echo "$JSON" | jq -r '.data."delta-status" // "UNKNOWN"')
  INTERVAL=$(echo "$JSON" | jq -r '.data."replication-interval" // 0')
  [[ "$STATE" == "ACTIVE" ]] || crit "$REP: state $STATE"
  case "$DELTA" in
    IDLE|CAPTURING|APPLYING) ok "$REP: delta status $DELTA, interval ${INTERVAL} min" ;;
    *)                       warn "$REP: delta status $DELTA" ;;
  esac
done

# --- R7: OCI Object Storage — Replication Policy ----------------------------
echo
echo "[R7] OCI Object Storage - Replication Policy"
for SPEC in ${DR_BUCKET_POLICIES:-}; do
  BUCKET="${SPEC%%:*}"; POLICY="${SPEC##*:}"
  JSON=$(oci os replication get-replication-policy --bucket-name "$BUCKET" \
           --replication-id "$POLICY" --namespace "${DR_OS_NAMESPACE:?}" 2>/dev/null)
  if [[ -z "$JSON" ]]; then crit "$BUCKET: policy not readable"; continue; fi
  STATUS=$(echo "$JSON" | jq -r '.data.status')
  case "$STATUS" in
    ACTIVE) ok "$BUCKET: replication ACTIVE" ;;
    *)      crit "$BUCKET: replication status $STATUS" ;;
  esac
done

# --- R12: Oracle Cloud Agent Run Command plugin -----------------------------
echo
echo "[R12] Oracle Cloud Agent - Run Command plugin"
for OCID in ${DR_APP_INSTANCE_OCIDS:-}; do
  STATE=$(oci instance-agent plugin get --instanceagent-id "$OCID" \
            --plugin-name "Run Command" --region "$DR_REGION" \
            --compartment-id "${DR_COMPARTMENT_OCID:?}" 2>/dev/null \
            | jq -r '.data.status // "UNREADABLE"')
  case "$STATE" in
    RUNNING)    ok   "$OCID: Run Command RUNNING" ;;
    UNREADABLE) warn "$OCID: plugin state unreadable (instance may be stopped -- expected in WARM)" ;;
    *)          crit "$OCID: Run Command $STATE -- FSDR user-defined steps will fail" ;;
  esac
done

# --- R2: Autonomous Recovery Service ----------------------------------------
echo
echo "[R2] Oracle Database Autonomous Recovery Service"
for PDB in ${DR_PROTECTED_DB_OCIDS:-}; do
  JSON=$(oci recovery protected-database get --protected-database-id "$PDB" 2>/dev/null)
  if [[ -z "$JSON" ]]; then crit "$PDB: not readable"; continue; fi
  HEALTH=$(echo "$JSON" | jq -r '.data.health // "UNKNOWN"')
  [[ "$HEALTH" == "PROTECTED" ]] && ok "$PDB: $HEALTH" || crit "$PDB: health $HEALTH"
done

echo
echo "=== Summary ==="
if   [[ $CRIT -eq 1 ]]; then echo "RESULT: CRITICAL -- do not consider the DR estate ready."; exit 2
elif [[ $WARN -eq 1 ]]; then echo "RESULT: WARNINGS -- investigate before the next drill."; exit 1
else                         echo "RESULT: ALL GREEN"; exit 0
fi
