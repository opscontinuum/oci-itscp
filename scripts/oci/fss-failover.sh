#!/usr/bin/env bash
# fss-failover.sh — R5: unlock an OCI File Storage replication TARGET for write by
# deleting the File System Replication resource. Part of RB-02 §4.
#
# The target file system is read-only while the replication resource exists.
# Deleting it is the documented way to make it writable -- and it is irreversible
# without a full re-baseline.
set -euo pipefail
source "$(dirname "$0")/storage-failover-lib.sh"

# Defaults come from terraform/dr-resources.env (sourced by the lib): the first replication
# in DR_FSS_REPLICATION_OCIDS and DR_REGION. Pass --replication to pick another.
REP=""; REGION=""; CONFIRM=0; TICKET=""; LOSSLESS=0; DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: fss-failover.sh [--replication <replication-ocid>] [--region <region>]
                       --ticket "<change-ref>" --confirm [--lossless] [--dry-run]

  --replication  Replication resource to delete. Default: the first OCID in
                 DR_FSS_REPLICATION_OCIDS from the resource config.
  --region       Region holding the replication. Default: DR_REGION from the config.
  --ticket       Change reference. Required: this action is irreversible and auditable.
  --confirm      Acknowledge the one-way door. Required.
  --lossless     Delete with --delete-mode ONE_MORE_CYCLE: one final replication cycle
                 runs first. For a planned switchover (RB-01) with a reachable source.
                 RB-02 never uses it -- in an unplanned failover the source is gone.
  --dry-run      Print the OCI calls without issuing them. Needs no credentials.

Exit codes: 0 done · 2 usage · 3 refused by a guard rail. See scripts/README.md.

Refused by design:
  Running without --confirm and --ticket.
  Any OCI operation absent from scripts/lib/write-guard.sh.
USAGE
}

while [[ $# -gt 0 ]]; do case "$1" in
  --replication) REP="$2"; shift 2 ;;
  --region)      REGION="$2"; shift 2 ;;
  --ticket)      TICKET="$2"; shift 2 ;;
  --lossless)    LOSSLESS=1; shift ;;
  --confirm)     CONFIRM=1; shift ;;
  --dry-run)     DRY_RUN=1; shift ;;
  -h|--help)     usage; exit 0 ;;
  *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac; done
WG_DRY_RUN=$DRY_RUN
REP="${REP:-${DR_FSS_REPLICATION_OCIDS%% *}}"
REGION="${REGION:-${DR_REGION:-}}"
[[ -n "$REP" && -n "$REGION" ]] || { echo "ERROR: --replication and --region required (or set DR_FSS_REPLICATION_OCIDS and DR_REGION in the config)" >&2; exit 2; }

require_confirm "delete FSS replication $REP (unlocks target for write)" "$CONFIRM"
require_ticket  "delete FSS replication $REP (unlocks target for write)" "$TICKET"
wg_authorise "$CONFIRM" "$TICKET"

echo "-> Current replication state"
if [[ $DRY_RUN -eq 1 ]]; then
  wg_oci fs replication get --replication-id "$REP" --region "$REGION" >/dev/null
else
  wg_oci fs replication get --replication-id "$REP" --region "$REGION" \
    | jq -r '.data | "   state: \(.["lifecycle-state"])  delta: \(.["delta-status"])  last-snap: \(.["recovery-point-time"] // "n/a")"'
fi

# Planned switchover (RB-01): --lossless uses --delete-mode ONE_MORE_CYCLE, which the CLI documents
# for lossless failover: one final replication cycle runs before the resource is deleted.
# Unplanned failover (RB-02): the source is gone; the default deletes immediately.
DELETE_MODE=()
[[ $LOSSLESS -eq 1 ]] && DELETE_MODE=(--delete-mode ONE_MORE_CYCLE)
echo "-> Deleting replication resource (target becomes writable)${LOSSLESS:+; lossless: one more cycle first}"
wg_oci fs replication delete --replication-id "$REP" --region "$REGION" "${DELETE_MODE[@]}" --force --wait-for-state DELETED

record "FileStorage/Replication" "$REP" "DELETED - target unlocked for write"
warn_failback_cost "OCI File Storage - File System Replication $REP"
echo "NEXT: mount the target file system on the Windows nodes and verify write access."
