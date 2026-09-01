#!/usr/bin/env bash
#
# detect-drift.sh — weekly Ashburn-versus-Phoenix configuration drift report.
# Part of docs/04-monitoring.md §5 and the RB-03 §4 failback reconciliation.
#
# GOVERNING RULE: drift is the quiet killer. Replication can be green in every
# dashboard while the failed-over application does not work, because the two
# regions diverged in ways no replica carries: image age, agent versions, NSG
# rules, EBS patch level, FND_NODES. This script is READ-ONLY; it produces a
# report with findings that must be treated as defects with owners.
#
# What it compares (each section degrades gracefully when a tool is absent):
#   A. Infrastructure   terraform plan -detailed-exitcode (if terraform/ has code)
#   B. Compute pairs    shape, OCPU/memory, image, Oracle Cloud Agent plugin config
#   C. Custom images    age of the newest Phoenix copy vs the newest Ashburn image
#   D. NSG rules        security rules diff per configured NSG pair
#   E. EBS              adop cycle state, patch count, FND_NODES (needs sqlplus)
#   F. In-guest         delegated to scripts/windows/Compare-NodeDrift.ps1
#
# Exit codes: 0 = no drift, 1 = drift found (report written), 3 = config/tooling.
# Requires: OCI CLI configured, jq. Optional: terraform, sqlplus.
#
set -uo pipefail

CONFIG="${DR_CONFIG:-$(dirname "$0")/../../terraform/dr-resources.env}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT=""
DRY_RUN=0
IMAGE_MAX_AGE_DAYS=30

usage() {
  cat <<'USAGE'
Usage: detect-drift.sh --report <file> [--image-max-age-days N] [--dry-run]

  --report               Markdown report path, e.g. evidence/drift-2026-09-01.md. Required.
  --image-max-age-days   Flag the Phoenix custom image if older than this. Default 30.
  --dry-run              Print the OCI calls without executing them.

Refused by design:
  This script never changes anything. Remediation goes through Terraform and
  image publishing, not through hand edits in the DR region (RB-03 §4).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)             REPORT="$2"; shift 2 ;;
    --image-max-age-days) IMAGE_MAX_AGE_DAYS="$2"; shift 2 ;;
    --dry-run)            DRY_RUN=1; shift ;;
    -h|--help)            usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -n "$REPORT" ]] || { usage; exit 2; }

[[ -f "$CONFIG" ]] || { echo "ERROR: resource config not found: $CONFIG" >&2; exit 3; }
# shellcheck source=/dev/null
source "$CONFIG"
: "${PRIMARY_REGION:?set PRIMARY_REGION}"; : "${DR_REGION:?set DR_REGION}"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DRIFT=0
FINDINGS=()   # "severity|area|detail|remediation"

finding() {
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] would flag [$1] $2: $3"; return; fi
  FINDINGS+=("$1|$2|$3|$4"); DRIFT=1; echo "  !! [$1] $2: $3"
}
ok()      { echo "  ok $*"; }

ocical() {
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] oci $*" >&2; echo ""; return; fi
  timeout 90 oci "$@" 2>/dev/null || echo ""
}

assert_read_only() {
  if grep -qE '^[^#]*oci [a-z -]+ (create|update|delete|launch|terminate|action)\b' "$0"; then
    echo "REFUSED: detect-drift.sh must remain read-only." >&2; exit 3
  fi
}
assert_read_only

echo "=== Drift detection · $TS · $PRIMARY_REGION vs $DR_REGION ==="

# --- A. Infrastructure (Terraform) ------------------------------------------
echo "[A] Infrastructure as code"
if command -v terraform >/dev/null 2>&1 && ls "$REPO_ROOT"/terraform/*.tf >/dev/null 2>&1; then
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] terraform -chdir=$REPO_ROOT/terraform plan -detailed-exitcode -input=false"
  else
    terraform -chdir="$REPO_ROOT/terraform" plan -detailed-exitcode -input=false -no-color >/tmp/drift-tf-plan.$$ 2>&1
    case $? in
      0) ok "terraform plan: no changes" ;;
      2) finding "HIGH" "Terraform" "plan shows pending changes -- live estate has diverged from code" "Review $REPO_ROOT/terraform plan output; apply through change control" ;;
      *) finding "MEDIUM" "Terraform" "plan failed to run ($(tail -1 /tmp/drift-tf-plan.$$))" "Fix the Terraform workspace before trusting the rest of this report" ;;
    esac
    rm -f /tmp/drift-tf-plan.$$
  fi
else
  echo "  skipped: terraform not on PATH or no *.tf under terraform/ (Terraform modules are planned build-out; see README §Status)"
fi

# --- B. Compute instance pairs ----------------------------------------------
# DR_NODE_PAIRS="<iad-instance-ocid>:<phx-instance-ocid> ..."  (same hostname, both regions)
echo "[B] Compute instance pairs"
for PAIR in ${DR_NODE_PAIRS:-}; do
  IAD="${PAIR%%:*}"; PHX="${PAIR##*:}"
  JI=$(ocical compute instance get --instance-id "$IAD" --region "$PRIMARY_REGION")
  JP=$(ocical compute instance get --instance-id "$PHX" --region "$DR_REGION")
  if [[ -z "$JI" || -z "$JP" ]]; then finding "MEDIUM" "Compute" "pair $PAIR unreadable" "Check OCIDs in DR_NODE_PAIRS"; continue; fi
  NAME=$(jq -r '.data."display-name"' <<<"$JI")
  for FIELD in '."shape"' '."shape-config"."ocpus"' '."shape-config"."memory-in-gbs"' '."agent-config"."is-monitoring-disabled"' '."agent-config"."is-management-disabled"'; do
    VI=$(jq -r ".data$FIELD // \"n/a\"" <<<"$JI"); VP=$(jq -r ".data$FIELD // \"n/a\"" <<<"$JP")
    [[ "$VI" == "$VP" ]] && ok "$NAME $FIELD = $VI" \
      || finding "HIGH" "Compute" "$NAME $FIELD differs: IAD=$VI PHX=$VP" "Align the Phoenix instance through Terraform, not the console"
  done
  # Run Command plugin must be enabled in BOTH regions or FSDR steps fail.
  for SIDE in IAD:"$JI" PHX:"$JP"; do
    J="${SIDE#*:}"; R="${SIDE%%:*}"
    RC=$(jq -r '.data."agent-config"."plugins-config" // [] | map(select(.name=="Compute Instance Run Command")) | .[0].desiredState // "UNSET"' <<<"$J")
    [[ "$RC" == "ENABLED" ]] && ok "$NAME $R Run Command plugin ENABLED" \
      || finding "HIGH" "Compute" "$NAME $R Run Command plugin desiredState=$RC" "Enable the plugin; every FSDR user-defined step on this node fails otherwise (docs/01 §6)"
  done
done
[[ -z "${DR_NODE_PAIRS:-}" ]] && echo "  skipped: DR_NODE_PAIRS not set in $CONFIG"

# --- C. Custom image age ----------------------------------------------------
echo "[C] Custom image age"
if [[ -n "${DR_IMAGE_NAME_PREFIX:-}" && -n "${DR_COMPARTMENT_OCID:-}" ]]; then
  JI=$(ocical compute image list --compartment-id "${PRIMARY_COMPARTMENT_OCID:-$DR_COMPARTMENT_OCID}" --region "$PRIMARY_REGION" --all --sort-by TIMECREATED --sort-order DESC)
  JP=$(ocical compute image list --compartment-id "$DR_COMPARTMENT_OCID" --region "$DR_REGION" --all --sort-by TIMECREATED --sort-order DESC)
  TI=$(jq -r --arg p "$DR_IMAGE_NAME_PREFIX" '[.data[] | select(."display-name" | startswith($p))] | .[0]."time-created" // empty' <<<"${JI:-{\}}")
  TP=$(jq -r --arg p "$DR_IMAGE_NAME_PREFIX" '[.data[] | select(."display-name" | startswith($p))] | .[0]."time-created" // empty' <<<"${JP:-{\}}")
  if [[ -z "$TP" ]]; then finding "HIGH" "Images" "no custom image with prefix '$DR_IMAGE_NAME_PREFIX' in $DR_REGION" "Copy the current image to Phoenix (RB-05 §2 Phase 4)"
  else
    AGE=$(( ( $(date -u +%s) - $(date -u -d "$TP" +%s) ) / 86400 ))
    [[ $AGE -le $IMAGE_MAX_AGE_DAYS ]] && ok "Phoenix image is $AGE days old" \
      || finding "MEDIUM" "Images" "Phoenix image is $AGE days old (> $IMAGE_MAX_AGE_DAYS)" "Publish and copy a fresh Custom Image"
    if [[ -n "$TI" && "$TI" > "$TP" ]]; then
      finding "MEDIUM" "Images" "Ashburn has a newer image ($TI) than Phoenix ($TP)" "Export the image to Object Storage, copy the object to Phoenix, import it there (docs/01 §4.2)"
    fi
  fi
else
  echo "  skipped: DR_IMAGE_NAME_PREFIX / DR_COMPARTMENT_OCID not set"
fi

# --- D. NSG rule diff -------------------------------------------------------
# DR_NSG_PAIRS="<iad-nsg-ocid>:<phx-nsg-ocid> ..."
echo "[D] Network security group rules"
for PAIR in ${DR_NSG_PAIRS:-}; do
  IAD="${PAIR%%:*}"; PHX="${PAIR##*:}"
  # Normalise: drop ids/timestamps, and map the CIDRs that legitimately differ (10.10/16 vs 10.20/16).
  NORM='[.data[] | {direction, protocol, source, destination, "is-stateless": ."is-stateless", "tcp-options": ."tcp-options", "udp-options": ."udp-options", "icmp-options": ."icmp-options"}] | sort_by(tostring)'
  RI=$(ocical network nsg rules list --nsg-id "$IAD" --region "$PRIMARY_REGION" --all | jq -c "$NORM" 2>/dev/null | sed 's/10\.10\./10.X./g')
  RP=$(ocical network nsg rules list --nsg-id "$PHX" --region "$DR_REGION" --all | jq -c "$NORM" 2>/dev/null | sed 's/10\.20\./10.X./g')
  if [[ -z "$RI" || -z "$RP" ]]; then finding "MEDIUM" "NSG" "pair $PAIR unreadable" "Check DR_NSG_PAIRS"; continue; fi
  [[ "$RI" == "$RP" ]] && ok "NSG pair rules identical (CIDR-normalised)" \
    || finding "HIGH" "NSG" "rules differ between $IAD and $PHX" "Diff against Terraform state; re-apply through code (RB-03 §4)"
done
[[ -z "${DR_NSG_PAIRS:-}" ]] && echo "  skipped: DR_NSG_PAIRS not set"

# --- E. EBS application state -----------------------------------------------
echo "[E] EBS patch and node state"
if command -v sqlplus >/dev/null 2>&1 && [[ -n "${APPS_CONNECT:-}" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then echo "  [dry-run] sqlplus $APPS_CONNECT (adop session state, AD_BUGS count, FND_NODES)"
  else
    E=$(sqlplus -s "$APPS_CONNECT" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT 'ADOP=' || NVL((SELECT MAX(status) FROM ad_adop_sessions WHERE status NOT IN ('C','X')), 'NONE') FROM dual;
SELECT 'BUGS=' || COUNT(*) FROM ad_bugs;
SELECT 'NODE=' || node_name || ':' || NVL(server_id,'-') FROM fnd_nodes WHERE node_name <> 'AUTHENTICATION' ORDER BY node_name;
exit
SQL
)
    ADOP=$(grep -oE 'ADOP=[^ ]+' <<<"$E" | cut -d= -f2)
    [[ "$ADOP" == "NONE" ]] && ok "no open adop cycle" \
      || finding "HIGH" "EBS" "adop session open (status $ADOP)" "Complete or abort the cycle; failover mid-cycle is refused (RB-02 §7a)"
    echo "  AD_BUGS count: $(grep -oE 'BUGS=[0-9]+' <<<"$E" | cut -d= -f2) (record; compare with last week)"
    if [[ -n "${DR_EXPECTED_NODES:-}" ]]; then
      for N in $DR_EXPECTED_NODES; do
        grep -qi "NODE=$N:" <<<"$E" && ok "FND_NODES has $N" \
          || finding "HIGH" "EBS" "FND_NODES missing expected node $N" "Identical-hostname design has drifted (docs/01 §5.1); expect the AutoConfig branch RB-02 §7b"
      done
    fi
  fi
else
  echo "  skipped: sqlplus not on PATH or APPS_CONNECT unset (run from an EBS node for section E)"
fi

# --- F. In-guest --------------------------------------------------------------
echo "[F] In-guest drift"
echo "  delegated: run scripts/windows/Compare-NodeDrift.ps1 -Mode Capture on each node pair, then -Mode Compare."
echo "  Covers scheduled tasks, local certificates, hotfixes, services, ODBC DSNs, Oracle Cloud Agent and JRE versions."

# --- report -----------------------------------------------------------------
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$(dirname "$REPORT")"
  {
    echo "# Drift report — $TS"
    echo
    echo "Compared \`$PRIMARY_REGION\` (primary) against \`$DR_REGION\` (DR). Generated by \`scripts/oci/detect-drift.sh\` (docs/04-monitoring.md §5)."
    echo
    if [[ ${#FINDINGS[@]} -eq 0 ]]; then
      echo "**No drift detected** in sections A–E. Section F (in-guest) requires \`Compare-NodeDrift.ps1\`."
    else
      echo "**${#FINDINGS[@]} finding(s).** Treat each as a defect with an owner and a due date, not as information."
      echo
      echo "| # | Severity | Area | Finding | Remediation | Owner | Due |"
      echo "|---|---|---|---|---|---|---|"
      i=0
      for F in "${FINDINGS[@]}"; do
        i=$((i+1)); IFS='|' read -r SEV AREA DET REM <<<"$F"
        echo "| $i | $SEV | $AREA | $DET | $REM | | |"
      done
    fi
    echo
    echo "## Section F — in-guest (manual)"
    echo
    echo "Attach the output of \`Compare-NodeDrift.ps1 -Mode Compare\` for every node pair here."
  } > "$REPORT"
  echo "=== Report written to $REPORT ==="
fi

exit $DRIFT
