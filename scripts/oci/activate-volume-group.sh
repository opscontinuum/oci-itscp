#!/usr/bin/env bash
# activate-volume-group.sh — R3: activate an OCI Block Volume Group Replica in
# Phoenix into an attachable volume group. Part of RB-01 §3 / RB-02 §4.
set -euo pipefail
source "$(dirname "$0")/storage-failover-lib.sh"

# Defaults come from terraform/dr-resources.env (sourced by the lib): the first replica in
# DR_VOLUME_GROUP_REPLICA_OCIDS and DR_REGION. Pass --vg-replica to pick another.
VGR=""; REGION=""; NAME=""; CONFIRM=0; TICKET=""; DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: activate-volume-group.sh [--vg-replica <ocid>] [--region <region>] [--name <vg-name>]
                                --ticket "<change-ref>" --confirm [--dry-run]

  --vg-replica  Volume group replica to activate. Default: the first OCID in
                DR_VOLUME_GROUP_REPLICA_OCIDS from the resource config.
  --region      Region holding the replica. Default: DR_REGION from the config.
  --name        Display name for the new volume group. Default: ebs-app-vg-activated-<UTC>.
  --ticket      Change reference. Required: this action is irreversible and auditable.
  --confirm     Acknowledge the one-way door. Required.
  --dry-run     Print the OCI calls without issuing them. Needs no credentials.

Exit codes: 0 done · 2 usage · 3 refused by a guard rail. See scripts/README.md.

Refused by design:
  Running without --confirm and --ticket.
  Any OCI operation absent from scripts/lib/write-guard.sh.
USAGE
}

while [[ $# -gt 0 ]]; do case "$1" in
  --vg-replica) VGR="$2"; shift 2 ;;
  --region)     REGION="$2"; shift 2 ;;
  --name)       NAME="$2"; shift 2 ;;
  --ticket)     TICKET="$2"; shift 2 ;;
  --confirm)    CONFIRM=1; shift ;;
  --dry-run)    DRY_RUN=1; shift ;;
  -h|--help)    usage; exit 0 ;;
  *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac; done
WG_DRY_RUN=$DRY_RUN
VGR="${VGR:-${DR_VOLUME_GROUP_REPLICA_OCIDS%% *}}"
REGION="${REGION:-${DR_REGION:-}}"
[[ -n "$VGR" && -n "$REGION" ]] || { echo "ERROR: --vg-replica and --region required (or set DR_VOLUME_GROUP_REPLICA_OCIDS and DR_REGION in the config)" >&2; exit 2; }
NAME="${NAME:-ebs-app-vg-activated-$(date -u +%Y%m%d%H%M)}"

require_confirm "activate volume group replica $VGR" "$CONFIRM"
require_ticket  "activate volume group replica $VGR" "$TICKET"
wg_authorise "$CONFIRM" "$TICKET"

echo "-> Reading replica state and last sync point"
if [[ $DRY_RUN -eq 1 ]]; then
  wg_oci bv volume-group-replica get --volume-group-replica-id "$VGR" --region "$REGION" >/dev/null
else
  wg_oci bv volume-group-replica get --volume-group-replica-id "$VGR" --region "$REGION" \
    | jq -r '.data | "   state: \(.["lifecycle-state"])  last-synced: \(.["time-last-synced"])"'
fi

echo "-> Activating replica into volume group: $NAME"
wg_oci bv volume-group create \
  --region "$REGION" \
  --compartment-id "${DR_COMPARTMENT_OCID:?set DR_COMPARTMENT_OCID}" \
  --display-name "$NAME" \
  --source-details "{\"type\":\"volumeGroupReplicaId\",\"volumeGroupReplicaId\":\"$VGR\"}" \
  --wait-for-state AVAILABLE

record "BlockVolume/VolumeGroupReplica" "$VGR" "ACTIVATED as $NAME"
warn_failback_cost "OCI Block Volume - Volume Group Replication for $VGR"
echo "NEXT: attach the volumes to the Windows nodes, then verify fs1, fs2 AND fs_ne are present."
