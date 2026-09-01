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
REP=""; REGION=""; CONFIRM=0; TICKET=""
while [[ $# -gt 0 ]]; do case "$1" in
  --replication) REP="$2"; shift 2 ;;
  --region)      REGION="$2"; shift 2 ;;
  # shellcheck disable=SC2034  # consumed by record() in storage-failover-lib.sh
  --ticket)      TICKET="$2"; shift 2 ;;
  --confirm)     CONFIRM=1; shift ;;
  *) echo "Usage: $0 [--replication <replication-ocid>] [--region <region>] [--ticket <change-ref>] --confirm" >&2; exit 2 ;;
esac; done
REP="${REP:-${DR_FSS_REPLICATION_OCIDS%% *}}"
REGION="${REGION:-${DR_REGION:-}}"
[[ -n "$REP" && -n "$REGION" ]] || { echo "ERROR: --replication and --region required (or set DR_FSS_REPLICATION_OCIDS and DR_REGION in the config)" >&2; exit 2; }

require_confirm "delete FSS replication $REP (unlocks target for write)" "$CONFIRM"

echo "-> Current replication state"
oci fs replication get --replication-id "$REP" --region "$REGION" \
  | jq -r '.data | "   state: \(.["lifecycle-state"])  delta: \(.["delta-status"])  last-snap: \(.["recovery-point-time"] // "n/a")"'

echo "-> Deleting replication resource (target becomes writable)"
oci fs replication delete --replication-id "$REP" --region "$REGION" --force --wait-for-state DELETED

record "FileStorage/Replication" "$REP" "DELETED - target unlocked for write"
warn_failback_cost "OCI File Storage - File System Replication $REP"
echo "NEXT: mount the target file system on the Windows nodes and verify write access."
