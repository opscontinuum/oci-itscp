#!/usr/bin/env bash
# objectstore-failover.sh — R7: make an OCI Object Storage DESTINATION bucket
# writable. Part of RB-02 §4.
#
# Two operations, in this order:
#   1. make-bucket-writable on the DESTINATION bucket (Phoenix). This is the
#      documented destination-side action and works even when the source region
#      is unreachable, which is the regional-loss case this runbook exists for.
#      Once done, the destination stops accepting replication from the source and
#      the source policy's status changes to a client error state.
#   2. delete-replication-policy on the SOURCE bucket (Ashburn), best-effort.
#      Deleting a policy is permanent. It fails harmlessly if Ashburn is down;
#      do it during RB-03 §2 instead.
#
# Re-establishing replication later does NOT copy objects that already exist
# in the source bucket: only objects uploaded after policy creation replicate.
# Failback therefore needs an explicit bulk copy first (RB-03 §2).
set -euo pipefail
source "$(dirname "$0")/storage-failover-lib.sh"

DEST_BUCKET=""; DEST_REGION=""; SRC_BUCKET=""; POLICY=""; SRC_REGION=""; NS=""; CONFIRM=0; TICKET=""; DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: objectstore-failover.sh --bucket <destination-bucket> --region <destination-region>
                               [--source-bucket <name> --policy <id> --source-region <region>]
                               [--namespace <ns>] --ticket "<change-ref>" --confirm [--dry-run]

  --bucket         DESTINATION bucket to make writable (Phoenix). Required.
  --region         Region of that bucket. Default: DR_REGION from the resource config.
  --source-bucket  SOURCE bucket (Ashburn), if its policy is to be deleted too.
  --policy         Replication policy id on the source bucket.
  --source-region  Region of the source bucket. Default: PRIMARY_REGION from the config.
  --namespace      Object Storage namespace. Default: DR_OS_NAMESPACE from the config.
  --ticket         Change reference. Required: this action is irreversible and auditable.
  --confirm        Acknowledge the one-way door. Required.
  --dry-run        Print the OCI calls without issuing them. Needs no credentials.

Exit codes: 0 done · 2 usage · 3 refused by a guard rail. See scripts/README.md.

Refused by design:
  Running without --confirm and --ticket.
  Any OCI operation absent from scripts/lib/write-guard.sh.
USAGE
}

while [[ $# -gt 0 ]]; do case "$1" in
  --bucket)         DEST_BUCKET="$2"; shift 2 ;;
  --region)         DEST_REGION="$2"; shift 2 ;;
  --source-bucket)  SRC_BUCKET="$2"; shift 2 ;;
  --policy)         POLICY="$2"; shift 2 ;;
  --source-region)  SRC_REGION="$2"; shift 2 ;;
  --namespace)      NS="$2"; shift 2 ;;
  --ticket)         TICKET="$2"; shift 2 ;;
  --confirm)        CONFIRM=1; shift ;;
  --dry-run)        DRY_RUN=1; shift ;;
  -h|--help)        usage; exit 0 ;;
  *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac; done
WG_DRY_RUN=$DRY_RUN
NS="${NS:-${DR_OS_NAMESPACE:-}}"
DEST_REGION="${DEST_REGION:-${DR_REGION:-}}"
SRC_REGION="${SRC_REGION:-${PRIMARY_REGION:-}}"
[[ -n "$DEST_BUCKET" && -n "$DEST_REGION" && -n "$NS" ]] || { echo "ERROR: --bucket, --region and --namespace required" >&2; exit 2; }

require_confirm "make destination bucket $DEST_BUCKET writable (breaks replication)" "$CONFIRM"
require_ticket  "make destination bucket $DEST_BUCKET writable (breaks replication)" "$TICKET"
wg_authorise "$CONFIRM" "$TICKET"

echo "-> Making destination bucket writable: $DEST_BUCKET @ $DEST_REGION"
wg_oci os replication make-bucket-writable --bucket-name "$DEST_BUCKET" --namespace "$NS" --region "$DEST_REGION"
record "ObjectStorage/DestinationBucket" "$DEST_BUCKET@$DEST_REGION" "MADE WRITABLE - replication from source broken"

if [[ -n "$SRC_BUCKET" && -n "$POLICY" && -n "$SRC_REGION" ]]; then
  echo "-> Deleting source replication policy (best-effort; fails harmlessly if $SRC_REGION is down)"
  # The 2>/dev/null below is what makes the live call best-effort and quiet. It would
  # also swallow the guard's dry-run output, so the dry run gets its own branch --
  # a dry run that silently omits one of the two operations is worse than no dry run.
  if [[ $DRY_RUN -eq 1 ]]; then
    wg_oci os replication delete-replication-policy --bucket-name "$SRC_BUCKET" --replication-id "$POLICY" \
      --namespace "$NS" --region "$SRC_REGION" --force
    record "ObjectStorage/ReplicationPolicy" "$SRC_BUCKET:$POLICY" "DELETED on source"
  elif wg_oci os replication delete-replication-policy --bucket-name "$SRC_BUCKET" --replication-id "$POLICY" \
       --namespace "$NS" --region "$SRC_REGION" --force 2>/dev/null; then
    record "ObjectStorage/ReplicationPolicy" "$SRC_BUCKET:$POLICY" "DELETED on source"
  else
    echo "   source policy not deleted (source unreachable?). Delete it in RB-03 §2 before creating the reverse policy."
  fi
else
  echo "-> Source policy not specified; delete it in RB-03 §2 before creating the reverse policy."
fi

warn_failback_cost "OCI Object Storage - replication to $DEST_BUCKET (existing objects will need a bulk copy before a new policy)"
echo "NEXT: verify EBS interface processes can write to $DEST_BUCKET."
