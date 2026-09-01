#!/usr/bin/env bash
# objectstore-failover.sh — R7: make an OCI Object Storage destination bucket
# writable by deleting its Replication Policy. Part of RB-02 §4.
set -euo pipefail
source "$(dirname "$0")/storage-failover-lib.sh"

BUCKET=""; POLICY=""; NS=""; REGION=""; CONFIRM=0
while [[ $# -gt 0 ]]; do case "$1" in
  --bucket)    BUCKET="$2"; shift 2 ;;
  --policy)    POLICY="$2"; shift 2 ;;
  --namespace) NS="$2"; shift 2 ;;
  --region)    REGION="$2"; shift 2 ;;
  --confirm)   CONFIRM=1; shift ;;
  *) echo "Usage: $0 --bucket <name> --policy <id> --namespace <ns> --region <region> --confirm" >&2; exit 2 ;;
esac; done
NS="${NS:-${DR_OS_NAMESPACE:-}}"
[[ -n "$BUCKET" && -n "$POLICY" && -n "$NS" ]] || { echo "ERROR: --bucket, --policy and --namespace required" >&2; exit 2; }

require_confirm "delete Object Storage replication policy on $BUCKET" "$CONFIRM"

echo "-> Current policy status"
oci os replication get-replication-policy --bucket-name "$BUCKET" --replication-id "$POLICY" \
  --namespace "$NS" ${REGION:+--region "$REGION"} \
  | jq -r '.data | "   status: \(.status)  destination: \(.["destination-bucket-name"]) @ \(.["destination-region-name"])"'

echo "-> Deleting replication policy (destination bucket becomes writable)"
oci os replication delete-replication-policy --bucket-name "$BUCKET" --replication-id "$POLICY" \
  --namespace "$NS" ${REGION:+--region "$REGION"} --force

record "ObjectStorage/ReplicationPolicy" "$BUCKET:$POLICY" "DELETED - destination writable"
warn_failback_cost "OCI Object Storage - Replication Policy on $BUCKET"
echo "NEXT: verify EBS interface processes can write to the destination bucket."
