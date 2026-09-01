#!/usr/bin/env bash
#
# steer-traffic.sh — move the external entry point between regions by editing
# the OCI Traffic Management FAILOVER steering policy. Part of RB-01 §3 step 4
# and RB-02 §2 ("Steer to Phoenix").
#
# GOVERNING RULE: DNS steering is the LAST step of a cutover, never the first.
# Steering users at a region whose application tier is not up produces an
# outage that looks exactly like the disaster you are recovering from. This
# script therefore refuses to steer at a target whose load balancer reports no
# healthy backends, unless you override it explicitly and give a reason.
#
# Mechanism: a FAILOVER steering policy answers with the highest-priority
# enabled answer whose health check passes. "Forcing" a region means disabling
# the other region's answer, so the policy has only one eligible answer.
# --target auto re-enables both and lets the health checks decide again.
#
# Reversible: yes -- this is not a one-way door, which is why it needs no
# --confirm. It still writes an evidence record, because where users were sent
# at any given minute is a question an auditor will ask.
#
# Requires: OCI CLI configured, jq.
#
set -euo pipefail

CONFIG="${DR_CONFIG:-$(dirname "$0")/../../terraform/dr-resources.env}"
EVIDENCE="${DR_EVIDENCE_DIR:-$(dirname "$0")/../../evidence}/traffic-steering-log.md"
TARGET=""
REASON=""
FORCE=0
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: steer-traffic.sh --target {phoenix|ashburn|auto} [--reason "text"] [--force-unhealthy] [--dry-run]

  --target            phoenix  -> disable the Ashburn answer; only Phoenix is eligible
                      ashburn  -> disable the Phoenix answer; only Ashburn is eligible
                      auto     -> enable both; health checks + priority decide (steady state)
  --reason            Free text for the evidence log. Required with --force-unhealthy.
  --force-unhealthy   Steer even if the target load balancer reports no healthy backends.
  --dry-run           Print the actions without executing them.

Refused by design:
  Steering at a region whose load balancer has zero healthy backends, unless
  --force-unhealthy AND --reason are given. Start the application tier first
  (RB-02 §5); steer last.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)          TARGET="$2"; shift 2 ;;
    --reason)          REASON="$2"; shift 2 ;;
    --force-unhealthy) FORCE=1; shift ;;
    --dry-run)         DRY_RUN=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$TARGET" ]] || { usage; exit 2; }
[[ "$TARGET" =~ ^(phoenix|ashburn|auto)$ ]] || { echo "Invalid target: $TARGET" >&2; exit 2; }
if [[ $FORCE -eq 1 && -z "$REASON" ]]; then echo "ERROR: --force-unhealthy requires --reason (audit trail)." >&2; exit 2; fi

[[ -f "$CONFIG" ]] || { echo "ERROR: resource config not found: $CONFIG" >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONFIG"

: "${DR_STEERING_POLICY_OCID:?set DR_STEERING_POLICY_OCID in $CONFIG}"
: "${DR_STEERING_ANSWER_IAD:?set DR_STEERING_ANSWER_IAD (answer name for the Ashburn LB)}"
: "${DR_STEERING_ANSWER_PHX:?set DR_STEERING_ANSWER_PHX (answer name for the Phoenix LB)}"

run() {
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] $*"; else echo "  + $*"; "$@"; fi
}

# --- guard rails ------------------------------------------------------------

assert_target_healthy() {
  # assert_target_healthy <lb-ocid> <backend-set> <region>
  local lb="$1" bs="$2" region="$3"
  [[ -z "$lb" || -z "$bs" ]] && { echo "  (no LB configured for health gate; skipping)"; return; }
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] oci lb backend-set-health get --load-balancer-id $lb --backend-set-name $bs --region $region"; return; fi
  local j status
  j=$(oci lb backend-set-health get --load-balancer-id "$lb" --backend-set-name "$bs" --region "$region" 2>/dev/null || echo '{}')
  status=$(jq -r '.data.status // "UNKNOWN"' <<<"$j")
  echo "  target LB backend set health: $status"
  if [[ "$status" == "CRITICAL" || "$status" == "UNKNOWN" ]]; then
    if [[ $FORCE -eq 1 ]]; then
      echo "  !! WARNING: steering at an unhealthy target under --force-unhealthy (reason: $REASON)" >&2
      return
    fi
    cat >&2 <<ERR

REFUSED: the target load balancer backend set reports '$status'.

Steering users at a region whose application tier is not responding does not
recover the service; it moves the outage. Bring the tier up first (RB-02 §5,
validation pack RB-01 §5), then steer. If you have verified the tier by other
means and the health check itself is the problem, re-run with
--force-unhealthy --reason "<why>".
ERR
    exit 3
  fi
}

record_evidence() {
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local forced line; forced=no; [[ $FORCE -eq 1 ]] && forced=yes
  line="| $ts | $TARGET | ${REASON:-} | $forced | ${USER:-unknown} |"
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] evidence: $line"; return; fi
  [[ -f "$EVIDENCE" ]] || printf '# Traffic Steering Log\n\n| UTC timestamp | Target | Reason | Forced past health gate | Operator |\n|---|---|---|---|---|\n' > "$EVIDENCE"
  echo "$line" >> "$EVIDENCE"
}

# --- main -------------------------------------------------------------------

echo "=== Traffic steering · target: $TARGET ==="

case "$TARGET" in
  phoenix) assert_target_healthy "${DR_LB_OCID:-}" "${DR_LB_BACKENDSET:-}" "${DR_REGION:?}" ;;
  ashburn) assert_target_healthy "${PRIMARY_LB_OCID:-}" "${PRIMARY_LB_BACKENDSET:-}" "${PRIMARY_REGION:?}" ;;
  auto)    echo "  auto: no health gate; health checks decide" ;;
esac

echo "-> Reading steering policy"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "  [dry-run] oci dns steering-policy get --steering-policy-id $DR_STEERING_POLICY_OCID"
  ANSWERS='[]'
else
  POLICY=$(oci dns steering-policy get --steering-policy-id "$DR_STEERING_POLICY_OCID")
  TEMPLATE=$(jq -r '.data.template' <<<"$POLICY")
  [[ "$TEMPLATE" == "FAILOVER" ]] || { echo "ERROR: steering policy template is '$TEMPLATE', expected FAILOVER (docs/01-architecture.md §5.2)." >&2; exit 1; }
  ANSWERS=$(jq -c '.data.answers' <<<"$POLICY")
  for name in "$DR_STEERING_ANSWER_IAD" "$DR_STEERING_ANSWER_PHX"; do
    jq -e --arg n "$name" 'map(select(.name == $n)) | length > 0' <<<"$ANSWERS" >/dev/null \
      || { echo "ERROR: answer '$name' not found in the steering policy. Check DR_STEERING_ANSWER_* in $CONFIG." >&2; exit 1; }
  done
fi

# Disable the answer(s) that must not be eligible; enable the rest.
case "$TARGET" in
  phoenix) DISABLE="$DR_STEERING_ANSWER_IAD" ;;
  ashburn) DISABLE="$DR_STEERING_ANSWER_PHX" ;;
  auto)    DISABLE="" ;;
esac
NEW_ANSWERS=$(jq -c --arg d "$DISABLE" 'map(."is-disabled" = (.name == $d))' <<<"$ANSWERS")

echo "-> Updating answers (disabled: ${DISABLE:-none})"
run oci dns steering-policy update --steering-policy-id "$DR_STEERING_POLICY_OCID" \
      --answers "$NEW_ANSWERS" --force --wait-for-state ACTIVE

record_evidence
echo "=== Steering set to '$TARGET'. Logged to $EVIDENCE ==="
echo "NOTE: resolver caches mean real cutover takes 5-15 min regardless of TTL (docs/01 §5.2)."
echo "      Verify from OUTSIDE the region: dig +short <ebs-fqdn> from a Phoenix and an Internet vantage point."
