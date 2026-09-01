#!/usr/bin/env bash
#
# capture-replication-state.sh — forensic capture of every OCI storage-tier
# replica's last sync point at the moment of loss. Part of RB-02 §1.
#
# GOVERNING RULE: READ-ONLY, always. It runs BEFORE the one-way-door storage
# activations in RB-02 §4 (activate volume group, delete FSS replication,
# delete bucket policy), because those actions destroy the replication
# resources that hold the timestamps this script records. Together with
# scripts/dataguard/capture-lag-snapshot.sh it produces the data-loss
# statement Finance will require (RB-02 §6).
#
# Best-effort by design: a resource that cannot be read is recorded as
# unreadable. Partial evidence beats none.
#
# Requires: OCI CLI configured, jq.
#
set -uo pipefail

CONFIG="${DR_CONFIG:-$(dirname "$0")/../../terraform/dr-resources.env}"
EVIDENCE_DIR="${DR_EVIDENCE_DIR:-$(dirname "$0")/../../evidence}"
OUT=""
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: capture-replication-state.sh [--out <file>] [--dry-run]

  --out       Evidence file to write. Default: evidence/replication-state-<UTC>.md
  --dry-run   Print the OCI calls without executing them.

No arguments are required. Run it in RB-02 §1, BEFORE RB-02 §4.

Refused by design:
  This script never creates, updates, activates or deletes a replication
  resource. The one-way-door actions live in activate-volume-group.sh,
  fss-failover.sh and objectstore-failover.sh, each behind --confirm.
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

[[ -f "$CONFIG" ]] || { echo "ERROR: resource config not found: $CONFIG" >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONFIG"
: "${DR_REGION:?set DR_REGION in $CONFIG}"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date -u +%s)"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="${OUT:-${EVIDENCE_DIR}/replication-state-${STAMP}.md}"

# --- guard rails ------------------------------------------------------------

assert_read_only() {
  if grep -qE '^[^#]*oci [a-z -]+ (create|update|delete|activate|delete-replication-policy|make-replication-policy)\b' "$0"; then
    echo "REFUSED: capture-replication-state.sh must remain read-only. A mutating OCI verb was found in the script body." >&2
    exit 3
  fi
}

# --- helpers ----------------------------------------------------------------

age_min() {
  # age_min <ISO-8601 timestamp> -> minutes since, or "n/a"
  local t="$1" e
  [[ -z "$t" || "$t" == "null" ]] && { echo "n/a"; return; }
  e=$(date -u -d "$t" +%s 2>/dev/null) || { echo "n/a"; return; }
  echo $(( (NOW_EPOCH - e) / 60 ))
}

row() { printf '| %s | %s | %s | %s | %s | %s |\n' "$@" >> "$OUT"; }

ocical() {
  # ocical <args...> -> JSON on stdout, or empty on failure / dry-run
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] oci $*" >&2; echo ""; return; fi
  timeout 60 oci "$@" 2>/dev/null || echo ""
}

# --- main -------------------------------------------------------------------

assert_read_only

if [[ $DRY_RUN -eq 1 ]]; then OUT=/dev/stdout; else mkdir -p "$(dirname "$OUT")"; fi

cat > "$OUT" <<HDR
# Storage replication state snapshot — ${TS}

**Purpose:** forensic capture at the moment of loss (RB-02 §1), taken BEFORE the storage
activations in RB-02 §4 destroy these replication resources. Captured by
\`${USER:-unknown}\` on \`$(hostname)\`. Region queried: \`${DR_REGION}\`.

The **Age** column is the potential data loss for that tier: everything written to the
Ashburn source after the recorded sync point is not in Phoenix.

| Matrix row | Resource | State | Last sync point (UTC) | Age (min) | Notes |
|---|---|---|---|---|---|
HDR

echo "=== Capturing replication state · $TS ==="

# R3 — OCI Block Volume Volume Group Replication
for VGR in ${DR_VOLUME_GROUP_REPLICA_OCIDS:-}; do
  echo "-> R3 volume group replica $VGR"
  J=$(ocical bv volume-group-replica get --volume-group-replica-id "$VGR" --region "$DR_REGION")
  if [[ -z "$J" ]]; then row "R3" "\`$VGR\`" "UNREADABLE" "" "n/a" "could not read replica"; continue; fi
  S=$(jq -r '.data."lifecycle-state" // "?"' <<<"$J")
  T=$(jq -r '.data."time-last-synced" // ""' <<<"$J")
  row "R3" "\`$VGR\`" "$S" "${T:-none}" "$(age_min "$T")" "volume group replica; activation is a one-way door"
done

# R5 — OCI File Storage File System Replication
for REP in ${DR_FSS_REPLICATION_OCIDS:-}; do
  echo "-> R5 FSS replication $REP"
  J=$(ocical fs replication get --replication-id "$REP" --region "$DR_REGION")
  if [[ -z "$J" ]]; then row "R5" "\`$REP\`" "UNREADABLE" "" "n/a" "could not read replication"; continue; fi
  S=$(jq -r '.data."lifecycle-state" // "?"' <<<"$J")
  D=$(jq -r '.data."delta-status" // "?"' <<<"$J")
  I=$(jq -r '.data."replication-interval" // "?"' <<<"$J")
  T=$(jq -r '.data."recovery-point-time" // ""' <<<"$J")
  row "R5" "\`$REP\`" "$S / delta $D" "${T:-none}" "$(age_min "$T")" "interval ${I} min; deleting the replication unlocks the target"
done

# R7 — OCI Object Storage Replication Policy
for SPEC in ${DR_BUCKET_POLICIES:-}; do
  BUCKET="${SPEC%%:*}"; POLICY="${SPEC##*:}"
  echo "-> R7 bucket $BUCKET policy $POLICY"
  J=$(ocical os replication get-replication-policy --bucket-name "$BUCKET" --replication-id "$POLICY" --namespace "${DR_OS_NAMESPACE:-}" ${PRIMARY_REGION:+--region "$PRIMARY_REGION"})
  if [[ -z "$J" ]]; then row "R7" "\`$BUCKET\`" "UNREADABLE" "" "n/a" "policy lives on the SOURCE bucket; unreadable if the source region is lost"; continue; fi
  S=$(jq -r '.data.status // "?"' <<<"$J")
  T=$(jq -r '.data."time-last-sync" // ""' <<<"$J")
  M=$(jq -r '.data."status-message" // ""' <<<"$J")
  row "R7" "\`$BUCKET\`" "$S" "${T:-none}" "$(age_min "$T")" "${M:-replication policy}"
done

# R2 — Oracle Database Autonomous Recovery Service
for PDB in ${DR_PROTECTED_DB_OCIDS:-}; do
  echo "-> R2 protected database $PDB"
  J=$(ocical recovery protected-database get --protected-database-id "$PDB")
  if [[ -z "$J" ]]; then row "R2" "\`$PDB\`" "UNREADABLE" "" "n/a" "could not read protected database"; continue; fi
  H=$(jq -r '.data.health // "?"' <<<"$J")
  S=$(jq -r '.data."lifecycle-state" // "?"' <<<"$J")
  T=$(jq -r '.data.metrics."backup-space-used-in-gbs" // "" | tostring' <<<"$J")
  R=$(jq -r '.data.metrics."current-retention-period-in-seconds" // "" | tostring' <<<"$J")
  row "R2" "\`$PDB\`" "$S / $H" "see ARS console for last backup" "n/a" "backup space ${T} GB; retention ${R} s; independent failure domain"
done

# R12 — Run Command plugin (not replication, but it gates every FSDR user-defined step)
for OCID in ${DR_APP_INSTANCE_OCIDS:-}; do
  echo "-> R12 Run Command plugin on $OCID"
  J=$(ocical instance-agent plugin get --instanceagent-id "$OCID" --plugin-name "Run Command" --region "$DR_REGION" --compartment-id "${DR_COMPARTMENT_OCID:-}")
  S=$(jq -r '.data.status // "UNREADABLE"' <<<"${J:-{\}}")
  row "R12" "\`$OCID\`" "$S" "n/a" "n/a" "instance may be STOPPED in WARM posture; verify after START"
done

cat >> "$OUT" <<'FTR'

## Reading this table during RB-02

- **R3 age** is the block-volume data loss: local files on the Windows nodes newer than the
  sync point are gone. Interface landing directories are the usual casualty (`docs/02` §6).
- **R5 age** bounds the shared-filesystem loss. Compare against the replication interval:
  an age much larger than the interval means replication had already stalled before the
  incident (`docs/04-monitoring.md` §1).
- **R7 age** bounds the inbound interface files that must be replayed (RB-02 §6).
- Carry the largest age forward into the data-loss statement in the lag snapshot.

NEXT: RB-02 §3 (database failover), then §4 (storage activation, each behind --confirm).
FTR

[[ $DRY_RUN -eq 0 ]] && echo "=== Snapshot written to $OUT ==="
exit 0
