#!/usr/bin/env bash
# activate-volume-group.sh — R3: activate an OCI Block Volume Group Replica in
# Phoenix into an attachable volume group. Part of RB-01 §3 / RB-02 §4.
set -euo pipefail
source "$(dirname "$0")/storage-failover-lib.sh"

# Defaults come from terraform/dr-resources.env (sourced by the lib): the first replica in
# DR_VOLUME_GROUP_REPLICA_OCIDS and DR_REGION. Pass --vg-replica to pick another.
VGR=""; REGION=""; NAME=""; CONFIRM=0; TICKET=""
while [[ $# -gt 0 ]]; do case "$1" in
  --vg-replica) VGR="$2"; shift 2 ;;
  --region)     REGION="$2"; shift 2 ;;
  --name)       NAME="$2"; shift 2 ;;
  # shellcheck disable=SC2034  # consumed by record() in storage-failover-lib.sh
  --ticket)     TICKET="$2"; shift 2 ;;
  --confirm)    CONFIRM=1; shift ;;
  *) echo "Usage: $0 [--vg-replica <ocid>] [--region <region>] [--name <vg-name>] [--ticket <change-ref>] --confirm" >&2; exit 2 ;;
esac; done
VGR="${VGR:-${DR_VOLUME_GROUP_REPLICA_OCIDS%% *}}"
REGION="${REGION:-${DR_REGION:-}}"
[[ -n "$VGR" && -n "$REGION" ]] || { echo "ERROR: --vg-replica and --region required (or set DR_VOLUME_GROUP_REPLICA_OCIDS and DR_REGION in the config)" >&2; exit 2; }
NAME="${NAME:-ebs-app-vg-activated-$(date -u +%Y%m%d%H%M)}"

require_confirm "activate volume group replica $VGR" "$CONFIRM"
require_ticket  "activate volume group replica $VGR" "$TICKET"
wg_authorise "$CONFIRM" "$TICKET"

echo "-> Reading replica state and last sync point"
wg_oci bv volume-group-replica get --volume-group-replica-id "$VGR" --region "$REGION" \
  | jq -r '.data | "   state: \(.["lifecycle-state"])  last-synced: \(.["time-last-synced"])"'

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
