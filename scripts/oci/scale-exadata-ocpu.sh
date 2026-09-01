#!/usr/bin/env bash
#
# scale-exadata-ocpu.sh — scale an ExaDB-D VM Cluster's OCPU count online.
# Part of RB-01 §3 (manual fallback) and RB-02 §2 (compute readiness).
#
# GOVERNING RULE: never 0 OCPU, and never below Oracle's per-VM minimum (2 OCPU
# per VM on X10M and earlier, 8 ECPU per VM on X11M). Setting a VM cluster to 0
# shuts it down, which stops Oracle Data Guard redo apply on the standby. The
# standby stops advancing while every dashboard and document still claims the
# Tier 1 RPO -- Tier 1 silently becomes Tier 3. See docs/02-mtd-tiers.md §4 and
# docs/03-replication-matrix.md §3b. This script refuses with exit 3.
#
# The configured floor (DR_OCPU_FLOOR) is a second, softer guard: it is the
# number the cost model and the RPO attestation assume. Going below it is
# refused too; change the config deliberately if the floor itself changes.
#
# Requires: OCI CLI configured, jq.
#
set -euo pipefail

CONFIG="${DR_CONFIG:-$(dirname "$0")/../../terraform/dr-resources.env}"
EVIDENCE="${DR_EVIDENCE_DIR:-$(dirname "$0")/../../evidence}/ocpu-scale-log.md"
CLUSTER=""
PER_NODE=""
TOTAL=""
REASON=""
DRY_RUN=0
NO_WAIT=0

usage() {
  cat <<'USAGE'
Usage: scale-exadata-ocpu.sh --cluster <name> (--ocpu-per-node N | --total-ocpu N)
                             [--reason "text"] [--no-wait] [--dry-run]

  --cluster        Logical cluster name from the resource config: the DB_UNIQUE_NAME
                   of the member it hosts, e.g. EBSPROD_PHX (DR) or EBSPROD_IAD (primary).
  --ocpu-per-node  Target OCPU per VM; multiplied by the cluster's node count.
  --total-ocpu     Target total OCPU for the cluster (alternative to --ocpu-per-node).
  --reason         Free text for the evidence log. Required when scaling DOWN.
  --no-wait        Return without waiting for the cluster to reach AVAILABLE.
  --dry-run        Print the actions without executing them.

Examples (RB-01 §3):
  scale-exadata-ocpu.sh --cluster EBSPROD_PHX --ocpu-per-node 16
  scale-exadata-ocpu.sh --cluster EBSPROD_PHX --total-ocpu 4 --reason "return to floor, CHG0012345"

Refused by design:
  0 OCPU (shuts the cluster down, stops redo apply, voids the RPO).
  Anything below Oracle's per-VM minimum (DR_OCPU_MIN_PER_VM, default 2).
  Any target below DR_OCPU_FLOOR / PRIMARY_OCPU_FLOOR from the config.
  Scaling the primary cluster below its floor during business hours is not
  prevented here -- that is a change-management decision, and this script
  records the reason so the change can be audited.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)       CLUSTER="$2";  shift 2 ;;
    --ocpu-per-node) PER_NODE="$2"; shift 2 ;;
    --total-ocpu)    TOTAL="$2";    shift 2 ;;
    --reason)        REASON="$2";   shift 2 ;;
    --no-wait)       NO_WAIT=1;     shift ;;
    --dry-run)       DRY_RUN=1;     shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$CLUSTER" ]] || { usage; exit 2; }
if [[ -n "$PER_NODE" && -n "$TOTAL" ]]; then echo "ERROR: give --ocpu-per-node OR --total-ocpu, not both" >&2; exit 2; fi
if [[ -z "$PER_NODE" && -z "$TOTAL" ]]; then echo "ERROR: --ocpu-per-node or --total-ocpu is required" >&2; usage; exit 2; fi
for v in "$PER_NODE" "$TOTAL"; do
  [[ -z "$v" || "$v" =~ ^[0-9]+$ ]] || { echo "ERROR: OCPU value must be a non-negative integer: $v" >&2; exit 2; }
done

[[ -f "$CONFIG" ]] || { echo "ERROR: resource config not found: $CONFIG" >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONFIG"

# --- resolve the cluster ----------------------------------------------------

case "$CLUSTER" in
  "${DG_STANDBY_REMOTE:-EBSPROD_PHX}")
    VMC="${DR_VMCLUSTER_OCID:?set DR_VMCLUSTER_OCID}"; REGION="${DR_REGION:?set DR_REGION}"
    FLOOR="${DR_OCPU_FLOOR:?set DR_OCPU_FLOOR}"; PROD="${DR_OCPU_PRODUCTION:-}"; NODES_CFG="${DR_VMCLUSTER_NODE_COUNT:-}"; MIN_PER_VM="${DR_OCPU_MIN_PER_VM:-2}" ;;
  "${DG_PRIMARY:-EBSPROD_IAD}")
    VMC="${PRIMARY_VMCLUSTER_OCID:?set PRIMARY_VMCLUSTER_OCID for the primary cluster}"; REGION="${PRIMARY_REGION:?set PRIMARY_REGION}"
    FLOOR="${PRIMARY_OCPU_FLOOR:-2}"; PROD="${PRIMARY_OCPU_PRODUCTION:-}"; NODES_CFG="${PRIMARY_VMCLUSTER_NODE_COUNT:-}"; MIN_PER_VM="${PRIMARY_OCPU_MIN_PER_VM:-2}" ;;
  *) echo "ERROR: unknown cluster '$CLUSTER'. Expected ${DG_STANDBY_REMOTE:-EBSPROD_PHX} or ${DG_PRIMARY:-EBSPROD_IAD} (from $CONFIG)." >&2; exit 2 ;;
esac

run() {
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] $*"; else echo "  + $*"; "$@"; fi
}

# --- guard rails ------------------------------------------------------------

assert_ocpu_floor() {
  local target="$1"
  if [[ "$target" -lt 1 ]]; then
    cat >&2 <<'ERR'
REFUSED: target OCPU count is 0.

Setting an ExaDB-D VM Cluster to 0 OCPU shuts the VM cluster down, which stops
Oracle Data Guard redo apply on the standby it hosts. The standby stops
advancing while every dashboard and document continues to claim the Tier 1
RPO. This converts Tier 1 into Tier 3 silently (docs/02-mtd-tiers.md §4,
docs/03-replication-matrix.md §3b).

If you genuinely intend to stop protecting this database, that is a
decommission (runbooks/RB-05-replication-lifecycle.md §5) and requires sign-off.
ERR
    exit 3
  fi
  if [[ -n "${NODES:-}" && "$NODES" =~ ^[0-9]+$ && "$NODES" -gt 0 && $(( target / NODES )) -lt "$MIN_PER_VM" ]]; then
    cat >&2 <<ERR
REFUSED: ${target} OCPU across ${NODES} VM(s) is below Oracle's minimum of ${MIN_PER_VM} per VM.

ExaDB-D enforces a per-VM minimum (2 OCPU per VM on X10M and earlier; 8 ECPU per
VM on X11M -- set DR_OCPU_MIN_PER_VM accordingly). Anything lower is either
rejected by the service or is 0, which shuts the cluster down.
ERR
    exit 3
  fi
  if [[ -n "${NODES:-}" && "$NODES" =~ ^[0-9]+$ && "$NODES" -gt 0 && $(( target % (MIN_PER_VM * NODES) )) -ne 0 ]]; then
    echo "REFUSED: ${target} is not a multiple of ${MIN_PER_VM} per VM across ${NODES} VMs (ExaDB-D scales in multiples of ${MIN_PER_VM} per database server; the API rejects other values)." >&2
    exit 3
  fi
  if [[ "$target" -lt "$FLOOR" ]]; then
    cat >&2 <<ERR
REFUSED: target ${target} OCPU is below the configured floor of ${FLOOR} for ${CLUSTER}.

The floor is the number the cost model (docs/05-cost-and-teardown.md §2) and the
RPO attestation (docs/04-monitoring.md §4) assume keeps redo apply healthy. If
the floor itself is changing, edit ${CONFIG} deliberately, under a change record,
and re-run. Do not work around it here.
ERR
    exit 3
  fi
}

record_evidence() {
  local from="$1" to="$2" ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local line="| $ts | $CLUSTER | $from | $to | ${REASON:-} | ${USER:-unknown} |"
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] evidence: $line"; return; fi
  [[ -f "$EVIDENCE" ]] || printf '# ExaDB-D OCPU Scale Log\n\n| UTC timestamp | Cluster | From OCPU | To OCPU | Reason | Operator |\n|---|---|---|---|---|---|\n' > "$EVIDENCE"
  echo "$line" >> "$EVIDENCE"
}

# --- main -------------------------------------------------------------------

echo "=== ExaDB-D OCPU scaling · $CLUSTER · $REGION ==="

CURRENT="?"; NODES="$NODES_CFG"
if [[ $DRY_RUN -eq 0 ]]; then
  J=$(oci db cloud-vm-cluster get --cloud-vm-cluster-id "$VMC" --region "$REGION")
  CURRENT=$(jq -r '.data."cpu-core-count" // "?"' <<<"$J")
  [[ -z "$NODES" ]] && NODES=$(jq -r '.data."node-count" // (.data."db-servers" | length) // empty' <<<"$J")
  STATE=$(jq -r '.data."lifecycle-state"' <<<"$J")
  echo "-> current: ${CURRENT} OCPU across ${NODES:-?} node(s), state ${STATE}"
  [[ "$STATE" == "AVAILABLE" ]] || { echo "ERROR: cluster is $STATE, not AVAILABLE. Wait for the previous operation to finish." >&2; exit 1; }
fi

if [[ -n "$PER_NODE" ]]; then
  : "${NODES:?node count unknown -- set DR_VMCLUSTER_NODE_COUNT / PRIMARY_VMCLUSTER_NODE_COUNT in $CONFIG, or use --total-ocpu}"
  TOTAL=$(( PER_NODE * NODES ))
  echo "-> target: ${PER_NODE} OCPU/node x ${NODES} nodes = ${TOTAL} OCPU"
else
  echo "-> target: ${TOTAL} OCPU total"
fi

assert_ocpu_floor "$TOTAL"

if [[ "$CURRENT" =~ ^[0-9]+$ ]]; then
  if [[ "$TOTAL" -lt "$CURRENT" && -z "$REASON" ]]; then
    echo "ERROR: --reason is required when scaling DOWN (audit trail, docs/05 §5)." >&2; exit 2
  fi
  [[ "$TOTAL" -eq "$CURRENT" ]] && { echo "-> already at ${TOTAL} OCPU; nothing to do"; record_evidence "$CURRENT" "$TOTAL"; exit 0; }
fi
if [[ -n "$PROD" && "$TOTAL" -gt "$PROD" ]]; then
  echo "  !! WARNING: ${TOTAL} exceeds the configured production level (${PROD}). Proceeding; check the cost model." >&2
fi

echo "-> Scaling ${CLUSTER} to ${TOTAL} OCPU (online, no downtime for running databases)"
if [[ $NO_WAIT -eq 1 ]]; then
  run oci db cloud-vm-cluster update --cloud-vm-cluster-id "$VMC" --cpu-core-count "$TOTAL" --region "$REGION"
else
  run oci db cloud-vm-cluster update --cloud-vm-cluster-id "$VMC" --cpu-core-count "$TOTAL" --region "$REGION" \
        --wait-for-state AVAILABLE --wait-for-state FAILED
fi

record_evidence "$CURRENT" "$TOTAL"
echo "=== Done. Logged to $EVIDENCE ==="
echo "NOTE: redo apply continues throughout. Verify with scripts/dataguard/dg-health.sh after scaling down."
