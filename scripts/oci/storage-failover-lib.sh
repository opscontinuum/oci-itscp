#!/usr/bin/env bash
#
# storage-failover-lib.sh — shared guard rails for the three one-way-door
# storage failover actions (see docs/03-replication-matrix.md §2).
#
# Sourced by:
#   activate-volume-group.sh   (R3 — OCI Block Volume Volume Group Replication)
#   fss-failover.sh            (R5 — OCI File Storage File System Replication)
#   objectstore-failover.sh    (R7 — OCI Object Storage Replication Policy)
#
# Each of those actions DESTROYS the replication relationship. Re-establishing it
# afterwards performs a FULL BASELINE COPY, not a delta. That is why every one of
# them requires --confirm and writes an evidence record.
#
set -euo pipefail

# Every OCI call in the three failover scripts goes through wg_oci(). The guard
# owns the allowlist and the --confirm / --ticket gate; the helpers below own
# the operator-facing refusal text and the evidence record.
# shellcheck source=../lib/write-guard.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/write-guard.sh"

EVIDENCE_DIR="${DR_EVIDENCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../evidence" && pwd)}"

# Resource inventory (DR_OS_NAMESPACE, DR_COMPARTMENT_OCID, regions). Optional here:
# each script validates the variables it actually needs.
CONFIG="${DR_CONFIG:-$(dirname "${BASH_SOURCE[0]}")/../../terraform/dr-resources.env}"
# shellcheck source=/dev/null
[[ -f "$CONFIG" ]] && source "$CONFIG"

# require_ticket <action-description> <ticket-value>
require_ticket() {
  local action="$1" ticket="$2"
  if [[ -z "$ticket" ]]; then
    cat >&2 <<ERR

REFUSED: '${action}' requires --ticket "<change-ref>".

Every irreversible action in this plan is auditable. evidence/storage-failover-log.md
records who did what and under which change; a row with no change reference cannot be
reconciled against the change record afterwards, which is exactly the question an
auditor asks about the one action nobody wants to own.

Re-run with --ticket "<change-ref>".
ERR
    exit 3
  fi
}

# require_confirm <action-description> <confirm-flag-value>
require_confirm() {
  local action="$1" confirmed="$2"
  if [[ "$confirmed" != "1" ]]; then
    cat >&2 <<ERR

REFUSED: '${action}' requires --confirm.

This is a ONE-WAY DOOR. Completing it destroys the replication relationship.
Re-establishing replication afterwards performs a FULL BASELINE COPY, not an
incremental resync — hours to days depending on data volume, during which the
estate is unprotected in that direction.

Only proceed if you are executing RB-02 (unplanned failover) or RB-01
(planned switchover) under an approved change.

Re-run with --confirm once that is true.
ERR
    exit 3
  fi
}

# TICKET may be set by the calling script (--ticket); it is written into the Notes column.
TICKET="${TICKET:-}"

# record <resource-type> <resource-id> <action> [notes]
record() {
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local f="${EVIDENCE_DIR}/storage-failover-log.md"
  if [[ "${WG_DRY_RUN:-0}" == "1" ]]; then
    echo "  [dry-run] evidence -> $f: $1 | $2 | $3 | ${TICKET:+ticket $TICKET; }${4:-}"
    return
  fi
  [[ -f "$f" ]] || printf '# Storage Failover Log\n\nOne-way-door actions. Each row implies a future full baseline copy.\n\n| UTC | Resource type | Resource | Action | Operator | Notes |\n|---|---|---|---|---|---|\n' > "$f"
  printf '| %s | %s | %s | %s | %s | %s |\n' \
    "$ts" "$1" "$2" "$3" "${USER:-unknown}" "${TICKET:+ticket $TICKET; }${4:-}" >> "$f"
  echo "  evidence recorded -> $f"
}

# warn_failback_cost <mechanism>
warn_failback_cost() {
  if [[ "${WG_DRY_RUN:-0}" == "1" ]]; then
    echo
    echo "  [dry-run] nothing was destroyed. A live run would destroy: $1"
    echo "  [dry-run] and returning to Ashburn would then need a full reverse baseline of it."
    return
  fi
  cat <<NOTE

  ---------------------------------------------------------------------------
  FAILBACK COST INCURRED
  You have just destroyed: $1
  Returning to Ashburn now requires a full reverse baseline of this resource.
  Start it as soon as the region is available -- see RB-03 §2 entry criteria.
  ---------------------------------------------------------------------------
NOTE
}
