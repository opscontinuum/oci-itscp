#!/usr/bin/env bash
#
# set-dr-posture.sh — switch the Phoenix DR estate between named postures.
#
# Postures (see runbooks/RB-05-replication-lifecycle.md §1):
#   hot   — PHX Windows compute running, ExaDB-D at production OCPU.  Tier 0 readiness.
#   warm  — PHX Windows compute STOPPED, ExaDB-D at OCPU floor.       Steady state (default).
#   drill — Snapshot Standby + drill instances.                        RB-04 Level 2.
#
# GOVERNING RULE: this script tears down COMPUTE ONLY. It will never delete or
# suspend a replication resource. Deleting Volume Group Replication, FSS File
# System Replication, or an Object Storage Replication Policy forces a full
# baseline copy on re-enable — trading the cheapest line item on the bill for a
# multi-hour unprotected window. See docs/03-replication-matrix.md §3.
#
# Requires: OCI CLI configured, jq.
#
set -euo pipefail

# Every OCI call goes through wg_oci(); the guard owns the allowlist and
# fails closed on anything this plan does not ask for.
# shellcheck source=../lib/write-guard.sh
source "$(cd "$(dirname "$0")/../lib" && pwd)/write-guard.sh"

CONFIG="${DR_CONFIG:-$(dirname "$0")/../../terraform/dr-resources.env}"
POSTURE=""
REASON=""
DRY_RUN=0
EVIDENCE="$(dirname "$0")/../../evidence/posture-log.md"

usage() {
  cat <<'USAGE'
Usage: set-dr-posture.sh --posture {hot|warm|drill} [--reason "text"] [--dry-run]

  --posture   Target posture. Required.
  --reason    Free text, recorded in evidence/posture-log.md. Required for hot/drill.
  --dry-run   Print the actions without executing them.

Refused by design:
  Deleting replication resources. Use runbooks/RB-05 §5 (decommission) with sign-off.
  Scaling ExaDB-D to 0 OCPU. That stops redo apply and silently voids the RPO.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --posture) POSTURE="$2"; shift 2 ;;
    --reason)  REASON="$2";  shift 2 ;;
    --dry-run) DRY_RUN=1;    shift   ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -z "$POSTURE" ]] && { usage; exit 2; }
[[ "$POSTURE" =~ ^(hot|warm|drill)$ ]] || { echo "Invalid posture: $POSTURE" >&2; exit 2; }
if [[ "$POSTURE" != "warm" && -z "$REASON" ]]; then
  echo "ERROR: --reason is required for posture '$POSTURE' (audit trail)." >&2
  exit 2
fi

# shellcheck source=/dev/null
[[ -f "$CONFIG" ]] || { echo "ERROR: resource config not found: $CONFIG" >&2; exit 1; }
source "$CONFIG"

: "${DR_REGION:?set DR_REGION in $CONFIG}"
: "${DR_VMCLUSTER_OCID:?set DR_VMCLUSTER_OCID}"
: "${DR_OCPU_FLOOR:?set DR_OCPU_FLOOR}"
: "${DR_OCPU_PRODUCTION:?set DR_OCPU_PRODUCTION}"
: "${DR_APP_INSTANCE_OCIDS:?set DR_APP_INSTANCE_OCIDS (space-separated)}"

WG_DRY_RUN=$DRY_RUN
WG_REASON="$REASON"

# run() remains for non-OCI commands. OCI calls go through wg_oci().
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] $*"
  else
    echo "  + $*"
    "$@"
  fi
}

# --- guard rails ------------------------------------------------------------

assert_ocpu_sane() {
  local target="$1"
  if [[ "$target" -lt 1 ]]; then
    cat >&2 <<'ERR'
REFUSED: target OCPU count is below 1.

Scaling the standby ExaDB-D VM Cluster to 0 OCPU stops Oracle Data Guard redo
apply. The standby stops advancing while every dashboard and document continues
to claim the Tier 1 RPO. This converts Tier 1 into Tier 3 silently.

If you genuinely intend to stop protecting this database, that is a
decommission (runbooks/RB-05-replication-lifecycle.md §5) and requires sign-off.
ERR
    exit 3
  fi
}

assert_replication_untouched() {
  # Defensive: this script must never be extended to delete replication.
  # Fail loudly if someone has wired those verbs in.
  # The character class in the pattern keeps this line from matching itself.
  if grep -qE 'volume-group-replica[ ]delete|fs[ ]replication[ ]delete|delete-replication[-]policy|make-bucket[-]writable' "$0"; then
    echo "REFUSED: this script must not delete replication resources. See docs/03-replication-matrix.md §3." >&2
    exit 3
  fi
}

record_evidence() {
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local line="| $ts | $POSTURE | ${REASON:-steady state} | ${USER:-unknown} |"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] evidence: $line"
  else
    [[ -f "$EVIDENCE" ]] || printf '# DR Posture Log\n\n| UTC timestamp | Posture | Reason | Operator |\n|---|---|---|---|\n' > "$EVIDENCE"
    echo "$line" >> "$EVIDENCE"
  fi
}

scale_exadata() {
  local cores="$1"
  assert_ocpu_sane "$cores"
  echo "-> Scaling ExaDB-D VM Cluster to ${cores} OCPU (online)"
  # ExaDB-D in OCI is `cloud-vm-cluster`; `vm-cluster` is the Exadata Cloud@Customer group.
  wg_oci db cloud-vm-cluster update \
        --cloud-vm-cluster-id "$DR_VMCLUSTER_OCID" \
        --cpu-core-count "$cores" \
        --region "$DR_REGION" \
        --wait-for-state AVAILABLE
}

instances_action() {
  local action="$1"
  for ocid in $DR_APP_INSTANCE_OCIDS; do
    # Always-on instances (the BI tier that reads the standby every day) are never stopped.
    if [[ "$action" == "STOP" && " ${DR_ALWAYS_ON_INSTANCE_OCIDS:-} " == *" $ocid "* ]]; then
      echo "-> keep RUNNING (always-on) $ocid"; continue
    fi
    echo "-> ${action} ${ocid}"
    wg_oci compute instance action \
          --instance-id "$ocid" \
          --action "$action" \
          --region "$DR_REGION" \
          --wait-for-state "$([[ $action == START ]] && echo RUNNING || echo STOPPED)"
  done
}

verify_run_command_plugin() {
  echo "-> Verifying Oracle Cloud Agent Run Command plugin on started instances"
  for ocid in $DR_APP_INSTANCE_OCIDS; do
    if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] check plugin on $ocid"; continue; fi
    local state
    state=$(wg_oci instance-agent plugin get --instanceagent-id "$ocid" \
              --plugin-name "Run Command" --region "$DR_REGION" \
              --compartment-id "$DR_COMPARTMENT_OCID" 2>/dev/null \
              | jq -r '.data.status // "UNKNOWN"')
    if [[ "$state" != "RUNNING" ]]; then
      echo "  !! WARNING: Run Command plugin is '$state' on $ocid" >&2
      echo "     Every Full Stack DR user-defined step targeting this node will fail." >&2
    else
      echo "  ok $ocid"
    fi
  done
}

# --- postures ---------------------------------------------------------------

assert_replication_untouched

case "$POSTURE" in
  hot)
    echo "=== Posture: HOT (Tier 0 readiness) ==="
    scale_exadata "$DR_OCPU_PRODUCTION"
    instances_action START
    verify_run_command_plugin
    echo "NOTE: EBS services remain stopped. HOT means the platform is ready,"
    echo "      not that EBS is running. Starting EBS is a failover action (RB-02)."
    ;;

  warm)
    echo "=== Posture: WARM (steady state) ==="
    instances_action STOP
    scale_exadata "$DR_OCPU_FLOOR"
    echo "NOTE: All replication remains ACTIVE. Only compute was powered down."
    ;;

  drill)
    echo "=== Posture: DRILL (RB-04 Level 2) ==="
    : "${DR_DRILL_INSTANCE_OCIDS:?set DR_DRILL_INSTANCE_OCIDS for drill posture}"
    scale_exadata "$DR_OCPU_PRODUCTION"
    for ocid in $DR_DRILL_INSTANCE_OCIDS; do
      wg_oci compute instance action --instance-id "$ocid" --action START \
            --region "$DR_REGION" --wait-for-state RUNNING
    done
    cat <<'NEXT'

Next steps (not automated — they require a human decision point):
  1. dgmgrl> convert database EBSPROD_PHX to snapshot standby;
  2. Verify Fast Recovery Area headroom for the full drill duration.
  3. Start-EBSAppTier.ps1 -DrillMode   (enforces the five isolation controls;
     it aborts if any cannot be verified — see RB-04 §2)
NEXT
    ;;
esac

record_evidence
echo "=== Posture '$POSTURE' applied. Logged to $EVIDENCE ==="
