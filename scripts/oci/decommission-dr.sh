#!/usr/bin/env bash
#
# decommission-dr.sh — full decommission of the Phoenix DR estate.
# Implements runbooks/RB-05-replication-lifecycle.md §5. THE MOST DANGEROUS
# SCRIPT IN THIS REPOSITORY: it deliberately removes protection.
#
# GOVERNING RULES:
#   1. It refuses to run without --confirm-unprotected, an --approver and a
#      --ticket. Decommission requires written sign-off from the business
#      owner AND the risk function (checklists/dr-authority-matrix.md).
#   2. Evidence is archived and verified BEFORE anything is removed (RB-05 §5
#      step 8, moved first because it is the step that gets skipped).
#   3. Orchestration is destroyed FIRST, so nothing can fail over into a
#      half-dismantled estate (RB-05 §5 step 1).
#   4. Autonomous Recovery Service backups are RETAINED. This script contains
#      no verb that deletes a protected database or its backups, and it
#      asserts that about itself before running (RB-05 §5 step 6).
#   5. Every step is logged with approver and ticket to evidence/ (which by
#      then has been archived; the log is appended to the archive copy too).
#
# Order (RB-05 §5): archive evidence -> FSDR plans + DRPGs -> steering policy +
# health checks -> Phoenix Windows instances + volumes -> volume group / FSS /
# Object Storage replication -> Data Guard association + standby -> [ARS
# backups RETAINED] -> Phoenix VM cluster + Exadata infrastructure.
#
# Requires: OCI CLI configured, jq, tar. Optional: dgmgrl for the Broker step.
#
set -euo pipefail

CONFIG="${DR_CONFIG:-$(dirname "$0")/../../terraform/dr-resources.env}"
EVIDENCE_DIR="${DR_EVIDENCE_DIR:-$(dirname "$0")/../../evidence}"
LOG="${EVIDENCE_DIR}/decommission-log.md"
CONFIRM=0
APPROVER=""
TICKET=""
ARCHIVE=""
DRY_RUN=0
STOP_AFTER=99

usage() {
  cat <<'USAGE'
Usage: decommission-dr.sh --confirm-unprotected --approver "<name>" --ticket "<change-ref>"
                          [--evidence-archive <path.tar.gz>] [--stop-after <stage>] [--dry-run]

  --confirm-unprotected  Acknowledge that this REMOVES disaster recovery protection.
  --approver             Name of the signing approver (business owner + risk). Required.
  --ticket               Change reference. Required.
  --evidence-archive     Where to write the evidence tarball. Default: <evidence>/../evidence-archive-<UTC>.tar.gz
                         The archive is verified before stage 1 runs.
  --stop-after           Run stages 0..N then stop (1-7). Lets the decommission be
                         executed under separate change windows. Default: all.
  --dry-run              Print every action without executing it. ALWAYS do this first.

Stages:
  0  Archive and verify evidence/                 (RB-05 §5 step 8, run first)
  1  Delete Full Stack DR plans, then DRPGs       (step 1)
  2  Remove Traffic Management steering policy and health checks (step 2)
  3  Terminate Phoenix Windows instances + boot/block volumes    (step 3)
  4  Delete Volume Group, FSS and Object Storage replication     (step 4)
  5  Remove Data Guard association; drop the Phoenix standby     (step 5)
  6  RETAIN Autonomous Recovery Service backups -- nothing is executed (step 6)
  7  Delete the Phoenix VM cluster and Exadata infrastructure    (step 7)

Refused by design:
  Running without all three of --confirm-unprotected, --approver, --ticket.
  Deleting any Autonomous Recovery Service protected database or backup.
  Proceeding past stage 0 if the evidence archive cannot be read back.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm-unprotected) CONFIRM=1; shift ;;
    --approver)            APPROVER="$2"; shift 2 ;;
    --ticket)              TICKET="$2"; shift 2 ;;
    --evidence-archive)    ARCHIVE="$2"; shift 2 ;;
    --stop-after)          STOP_AFTER="$2"; shift 2 ;;
    --dry-run)             DRY_RUN=1; shift ;;
    -h|--help)             usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# --- guard rails ------------------------------------------------------------

require_signoff() {
  if [[ $CONFIRM -ne 1 || -z "$APPROVER" || -z "$TICKET" ]]; then
    cat >&2 <<'ERR'

REFUSED: decommission requires --confirm-unprotected, --approver and --ticket.

This script deliberately REMOVES disaster recovery protection for the EBS
estate. Re-establishing it afterwards is a full RB-05 §2 build: days of
baseline copies and a Level 2 drill before it can be called protected again.

It requires written sign-off from the business owner AND the risk function
(checklists/dr-authority-matrix.md, "Delete replication"). Record both on the
change ticket, then re-run with all three arguments. Run --dry-run first.
ERR
    exit 3
  fi
}

assert_backups_retained() {
  # Self-check: this file must never acquire a verb that deletes ARS backups.
  if grep -qE '^[^#]*oci recovery (protected-database|recovery-service-subnet|protection-policy) delete' "$0"; then
    echo "REFUSED: decommission-dr.sh must not delete Autonomous Recovery Service resources (RB-05 §5 step 6)." >&2
    exit 3
  fi
}

require_signoff
assert_backups_retained

[[ -f "$CONFIG" ]] || { echo "ERROR: resource config not found: $CONFIG" >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONFIG"
: "${DR_REGION:?set DR_REGION}"; : "${PRIMARY_REGION:?set PRIMARY_REGION}"

STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
ARCHIVE="${ARCHIVE:-$(cd "$EVIDENCE_DIR/.." && pwd)/evidence-archive-${STAMP}.tar.gz}"

run() {
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] $*"; else echo "  + $*"; "$@"; fi
}

log() {
  # log <stage> <action> <resource> <result>
  local ts line
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  line="| $ts | $1 | $2 | $3 | $4 | $APPROVER | $TICKET | ${USER:-unknown} |"
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] log: $line"; return; fi
  [[ -f "$LOG" ]] || printf '# DR Decommission Log\n\nEvery step below removed protection. Approver and ticket per RB-05 §5.\n\n| UTC | Stage | Action | Resource | Result | Approver | Ticket | Operator |\n|---|---|---|---|---|---|---|---|\n' > "$LOG"
  echo "$line" >> "$LOG"
}

stage_gate() { [[ "$1" -le "$STOP_AFTER" ]]; }

banner() { echo; echo "=================================================================="; echo "$*"; echo "=================================================================="; }

banner "DR DECOMMISSION · approver: $APPROVER · ticket: $TICKET · $([[ $DRY_RUN -eq 1 ]] && echo DRY-RUN || echo LIVE)"
echo "Region being dismantled: $DR_REGION. Primary $PRIMARY_REGION is NOT touched except to remove its Data Guard association and steering policy."

# --- Stage 0: archive evidence FIRST ----------------------------------------
if stage_gate 0; then
  banner "Stage 0 — archive evidence/ before anything is removed (RB-05 §5 step 8)"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] tar -czf $ARCHIVE -C $(dirname "$EVIDENCE_DIR") $(basename "$EVIDENCE_DIR")"
    echo "  [dry-run] tar -tzf $ARCHIVE >/dev/null   (verify)"
  else
    tar -czf "$ARCHIVE" -C "$(dirname "$EVIDENCE_DIR")" "$(basename "$EVIDENCE_DIR")"
    if ! tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
      echo "REFUSED: evidence archive $ARCHIVE cannot be read back. Nothing has been removed. Fix the archive and re-run." >&2
      exit 3
    fi
    echo "  archive verified: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
    if [[ -n "${DR_EVIDENCE_ARCHIVE_BUCKET:-}" ]]; then
      run oci os object put --bucket-name "$DR_EVIDENCE_ARCHIVE_BUCKET" --namespace "${DR_OS_NAMESPACE:?}" \
            --file "$ARCHIVE" --name "$(basename "$ARCHIVE")" --region "$PRIMARY_REGION" --force
    else
      echo "  NOTE: DR_EVIDENCE_ARCHIVE_BUCKET not set; archive is local only. Copy it to long-term retention before continuing."
    fi
  fi
  log 0 "archive evidence" "$ARCHIVE" "verified"
fi

# --- Stage 1: orchestration first -------------------------------------------
if stage_gate 1; then
  banner "Stage 1 — Full Stack DR plans, then DR Protection Groups (RB-05 §5 step 1)"
  for DRPG in ${DR_FSDR_DRPG_OCIDS:-}; do
    REG="$DR_REGION"; [[ "$DRPG" == *".iad."* ]] && REG="$PRIMARY_REGION"
    if [[ $DRY_RUN -eq 0 ]]; then
      PLANS=$(oci disaster-recovery dr-plan list --dr-protection-group-id "$DRPG" --region "$REG" --all 2>/dev/null | jq -r '.data.items[]?.id' || true)
    else PLANS="<plans of $DRPG>"; fi
    for P in $PLANS; do
      run oci disaster-recovery dr-plan delete --dr-plan-id "$P" --region "$REG" --force --wait-for-state SUCCEEDED
      log 1 "delete DR plan" "$P" "deleted"
    done
    # A DRPG must be disassociated from its peer before deletion.
    run oci disaster-recovery dr-protection-group disassociate --dr-protection-group-id "$DRPG" --region "$REG" --type DEFAULT --wait-for-state SUCCEEDED
    run oci disaster-recovery dr-protection-group delete --dr-protection-group-id "$DRPG" --region "$REG" --force --wait-for-state SUCCEEDED
    log 1 "delete DRPG" "$DRPG" "deleted"
  done
  [[ -z "${DR_FSDR_DRPG_OCIDS:-}" ]] && echo "  (DR_FSDR_DRPG_OCIDS not set; skipped)"
fi

# --- Stage 2: entry point ---------------------------------------------------
if stage_gate 2; then
  banner "Stage 2 — Traffic Management steering policy and health checks (step 2)"
  if [[ -n "${DR_STEERING_POLICY_OCID:-}" ]]; then
    if [[ $DRY_RUN -eq 0 ]]; then
      ATT=$(oci dns steering-policy-attachment list --steering-policy-id "$DR_STEERING_POLICY_OCID" --all 2>/dev/null | jq -r '.data[]?.id' || true)
    else ATT="<attachments of $DR_STEERING_POLICY_OCID>"; fi
    for A in $ATT; do run oci dns steering-policy-attachment delete --steering-policy-attachment-id "$A" --force; done
    run oci dns steering-policy delete --steering-policy-id "$DR_STEERING_POLICY_OCID" --force
    log 2 "delete steering policy" "$DR_STEERING_POLICY_OCID" "deleted"
  fi
  for HC in ${DR_HEALTH_CHECK_OCIDS:-}; do
    run oci health-checks http-monitor delete --monitor-id "$HC" --force
    log 2 "delete health check" "$HC" "deleted"
  done
  echo "  NOTE: the Ashburn DNS record now has no failover answer. Confirm the zone still resolves to the Ashburn LB."
fi

# --- Stage 3: Phoenix compute -----------------------------------------------
if stage_gate 3; then
  banner "Stage 3 — terminate Phoenix Windows instances and volumes (step 3)"
  for OCID in ${DR_APP_INSTANCE_OCIDS:-} ${DR_DRILL_INSTANCE_OCIDS:-}; do
    run oci compute instance terminate --instance-id "$OCID" --region "$DR_REGION" --preserve-boot-volume false --force --wait-for-state TERMINATED
    log 3 "terminate instance" "$OCID" "terminated (boot volume deleted)"
  done
  for VG in ${DR_ACTIVATED_VOLUME_GROUP_OCIDS:-}; do
    run oci bv volume-group delete --volume-group-id "$VG" --region "$DR_REGION" --force --wait-for-state TERMINATED
    log 3 "delete volume group" "$VG" "deleted"
  done
  run oci lb load-balancer delete --load-balancer-id "${DR_LB_OCID:?set DR_LB_OCID}" --region "$DR_REGION" --force --wait-for-state SUCCEEDED
  log 3 "delete load balancer" "$DR_LB_OCID" "deleted"
fi

# --- Stage 4: replication (the one-way doors, now intentionally) ------------
if stage_gate 4; then
  banner "Stage 4 — delete Volume Group, FSS and Object Storage replication (step 4)"
  echo "  These are the actions set-dr-posture.sh refuses. Here they are intentional and signed off."
  for VG in ${PRIMARY_VOLUME_GROUP_OCIDS:-}; do
    # Disabling replication on the SOURCE volume group removes the Phoenix replica.
    run oci bv volume-group update --volume-group-id "$VG" --region "$PRIMARY_REGION" --volume-group-replicas '[]' --force
    log 4 "disable volume group replication" "$VG" "replica removed"
  done
  for REP in ${DR_FSS_REPLICATION_OCIDS:-}; do
    run oci fs replication delete --replication-id "$REP" --region "$DR_REGION" --force --wait-for-state DELETED
    log 4 "delete FSS replication" "$REP" "deleted"
  done
  for SPEC in ${DR_BUCKET_POLICIES:-}; do
    BUCKET="${SPEC%%:*}"; POLICY="${SPEC##*:}"
    run oci os replication delete-replication-policy --bucket-name "$BUCKET" --replication-id "$POLICY" --namespace "${DR_OS_NAMESPACE:?}" --region "$PRIMARY_REGION" --force
    log 4 "delete bucket replication policy" "$BUCKET:$POLICY" "deleted"
  done
fi

# --- Stage 5: Data Guard ----------------------------------------------------
if stage_gate 5; then
  banner "Stage 5 — remove the Phoenix Data Guard member (step 5)"
  echo "  The Ashburn AD-2 SYNC standby (${DG_STANDBY_LOCAL:-EBSPROD_IAD2}) is local HA, not DR, and is NOT removed here."
  if [[ -n "${DR_DG_ASSOCIATION_OCID:-}" && -n "${PRIMARY_DATABASE_OCID:-}" ]]; then
    run oci db data-guard-association delete --database-id "$PRIMARY_DATABASE_OCID" --data-guard-association-id "$DR_DG_ASSOCIATION_OCID" --region "$PRIMARY_REGION" --force --wait-for-state TERMINATED
    log 5 "delete Data Guard association (drops ${DG_STANDBY_REMOTE:-EBSPROD_PHX})" "$DR_DG_ASSOCIATION_OCID" "deleted"
  elif command -v dgmgrl >/dev/null 2>&1 && [[ -n "${DG_CONNECT:-}" ]]; then
    run dgmgrl -silent "$DG_CONNECT" "remove database '${DG_STANDBY_REMOTE:-EBSPROD_PHX}'"
    log 5 "Broker remove database" "${DG_STANDBY_REMOTE:-EBSPROD_PHX}" "removed from configuration; drop the database in Phoenix manually"
  else
    echo "  skipped: set DR_DG_ASSOCIATION_OCID + PRIMARY_DATABASE_OCID, or run from a host with dgmgrl"
  fi
fi

# --- Stage 6: backups are RETAINED ------------------------------------------
if stage_gate 6; then
  banner "Stage 6 — Autonomous Recovery Service backups RETAINED (step 6)"
  cat <<'NOTE'
  Nothing is executed in this stage, by design. Backups are retained per the
  records-retention schedule (evidence/README.md §Retention). Deleting them
  with the infrastructure is the step that gets skipped and later regretted:
  the moment the DR estate is gone, the cross-region copy is the ONLY copy of
  the database outside Ashburn. Review retention with the risk function
  separately, under its own change, after the retention period.
NOTE
  log 6 "retain ARS backups" "${DR_PROTECTED_DB_OCIDS:-n/a}" "RETAINED (no action)"
fi

# --- Stage 7: Exadata -------------------------------------------------------
if stage_gate 7; then
  banner "Stage 7 — delete the Phoenix VM cluster and Exadata infrastructure (step 7)"
  run oci db cloud-vm-cluster delete --cloud-vm-cluster-id "${DR_VMCLUSTER_OCID:?}" --region "$DR_REGION" --force --wait-for-state TERMINATED
  log 7 "delete VM cluster" "$DR_VMCLUSTER_OCID" "deleted"
  if [[ -n "${DR_EXA_INFRA_OCID:-}" ]]; then
    run oci db cloud-exa-infra delete --cloud-exa-infra-id "$DR_EXA_INFRA_OCID" --region "$DR_REGION" --force --wait-for-state TERMINATED
    log 7 "delete Exadata infrastructure" "$DR_EXA_INFRA_OCID" "deleted"
  else
    echo "  DR_EXA_INFRA_OCID not set: infrastructure retained (check whether it is shared with another workload)."
  fi
fi

# Append the final log to the archive so the record of the decommission travels with the evidence.
if [[ $DRY_RUN -eq 0 && -f "$LOG" && $STOP_AFTER -ge 7 ]]; then
  cp "$LOG" "${ARCHIVE%.tar.gz}-decommission-log.md"
fi

banner "Decommission $([[ $STOP_AFTER -ge 7 ]] && echo COMPLETE || echo "paused after stage $STOP_AFTER"). The EBS estate has NO cross-region protection."
echo "Log: $LOG · Evidence archive: $ARCHIVE"
echo "Update docs/02-mtd-tiers.md: every tier is now Tier 3 (backup and restore) until a new estate is built (RB-05 §2)."
