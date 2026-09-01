#!/usr/bin/env bash
# activate-volume-group.sh — R3: activate an OCI Block Volume Group Replica in
# Phoenix into an attachable volume group. Part of RB-01 §3 / RB-02 §4.
set -euo pipefail
source "$(dirname "$0")/storage-failover-lib.sh"

VGR=""; REGION=""; NAME=""; CONFIRM=0
while [[ $# -gt 0 ]]; do case "$1" in
  --vg-replica) VGR="$2"; shift 2 ;;
  --region)     REGION="$2"; shift 2 ;;
  --name)       NAME="$2"; shift 2 ;;
  --confirm)    CONFIRM=1; shift ;;
  *) echo "Usage: $0 --vg-replica <ocid> --region <region> [--name <vg-name>] --confirm" >&2; exit 2 ;;
esac; done
[[ -n "$VGR" && -n "$REGION" ]] || { echo "ERROR: --vg-replica and --region required" >&2; exit 2; }
NAME="${NAME:-ebs-app-vg-activated-$(date -u +%Y%m%d%H%M)}"

require_confirm "activate volume group replica $VGR" "$CONFIRM"

echo "-> Reading replica state and last sync point"
oci bv volume-group-replica get --volume-group-replica-id "$VGR" --region "$REGION" \
  | jq -r '.data | "   state: \(.["lifecycle-state"])  last-synced: \(.["time-last-synced"])"'

echo "-> Activating replica into volume group: $NAME"
oci bv volume-group create \
  --region "$REGION" \
  --compartment-id "${DR_COMPARTMENT_OCID:?set DR_COMPARTMENT_OCID}" \
  --display-name "$NAME" \
  --source-details "{\"type\":\"volumeGroupReplicaId\",\"volumeGroupReplicaId\":\"$VGR\"}" \
  --wait-for-state AVAILABLE

record "BlockVolume/VolumeGroupReplica" "$VGR" "ACTIVATED as $NAME"
warn_failback_cost "OCI Block Volume - Volume Group Replication for $VGR"
echo "NEXT: attach the volumes to the Windows nodes, then verify fs1, fs2 AND fs_ne are present."
