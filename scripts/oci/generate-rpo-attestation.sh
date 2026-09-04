#!/usr/bin/env bash
#
# generate-rpo-attestation.sh — monthly RPO attestation from OCI Monitoring
# metric data. Part of docs/04-monitoring.md §4.
#
# GOVERNING RULE: report against the tier target, and report breaches honestly.
# A month showing three hours outside RPO with an explanation is credible; a
# month showing perfect compliance is not believed by anyone who has run
# infrastructure, and it removes the evidence needed to justify investment.
# This script therefore never suppresses, rounds away, or caps a breach.
#
# Data source: oci monitoring metric-data summarize-metrics-data, one MQL query
# per protected resource, at the resolution configured below. Metric namespaces
# and names differ by service and by tenancy feature set, so they are declared
# in the resource config (DR_RPO_METRICS) rather than hard-coded here. Confirm
# each against the OCI Monitoring metric reference for the service before
# trusting the first report -- a wrong metric name yields an empty series, and
# an empty series is reported as "NO DATA", never as compliance.
#
# READ-ONLY. Requires: OCI CLI configured, jq.
#
set -euo pipefail

# Read-only, and structurally so: every OCI call goes through wg_oci(), which
# refuses any mutating operation this script has no business issuing.
# shellcheck source=../lib/write-guard.sh
source "$(cd "$(dirname "$0")/../lib" && pwd)/write-guard.sh"

CONFIG="${DR_CONFIG:-$(dirname "$0")/../../terraform/dr-resources.env}"
MONTH=""
OUTDIR=""
DRY_RUN=0
RESOLUTION="5m"

usage() {
  cat <<'USAGE'
Usage: generate-rpo-attestation.sh --month YYYY-MM --out <dir> [--resolution 1m|5m|1h] [--dry-run]

  --month        Calendar month to attest, UTC. Required.
  --out          Directory for the report: <dir>/rpo-attestation-YYYY-MM.md. Required.
  --resolution   Metric resolution passed to OCI Monitoring. Default 5m.
  --dry-run      Print the MQL queries without executing them.

Config (terraform/dr-resources.env):
  DR_RPO_METRICS  One entry per line (or space-separated), each:
                    <label>|<tier-rpo-seconds>|<namespace>|<metric>|<dimension-filter>|<compartment-ocid>|<region>
                  e.g. "DataGuard PHX apply lag|30|oracle_oci_database|ApplyLag|primaryDbUniqueName = \"EBSPROD_IAD\"|ocid1.compartment...|us-phoenix-1"
                  (Data Guard lag metrics live in oracle_oci_database, emitted by Database Management
                  Diagnostics & Management; the base oci_database namespace has none.)

Refused by design:
  Reporting a resource with no data points as compliant. NO DATA is a finding.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --month)      MONTH="$2"; shift 2 ;;
    --out)        OUTDIR="$2"; shift 2 ;;
    --resolution) RESOLUTION="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -n "$MONTH" && -n "$OUTDIR" ]] || { usage; exit 2; }
[[ "$MONTH" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || { echo "ERROR: --month must be YYYY-MM" >&2; exit 2; }

[[ -f "$CONFIG" ]] || { echo "ERROR: resource config not found: $CONFIG" >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONFIG"
: "${DR_RPO_METRICS:?set DR_RPO_METRICS in $CONFIG (see --help)}"

START="${MONTH}-01T00:00:00Z"
END="$(date -u -d "${MONTH}-01 +1 month" +%Y-%m-01T00:00:00Z)"
REPORT="${OUTDIR%/}/rpo-attestation-${MONTH}.md"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

case "$RESOLUTION" in
  1m) STEP=60 ;; 5m) STEP=300 ;; 1h) STEP=3600 ;;
  *) echo "ERROR: --resolution must be 1m, 5m or 1h" >&2; exit 2 ;;
esac

assert_read_only() {
  if grep -qE '^[^#]*oci [a-z -]+ (create|update|delete)\b' "$0"; then
    echo "REFUSED: generate-rpo-attestation.sh must remain read-only." >&2; exit 3
  fi
}
assert_read_only

[[ $DRY_RUN -eq 0 ]] && mkdir -p "$OUTDIR"
ROWS=()
INTERRUPTIONS=()
BREACHES=0
NODATA=0

echo "=== RPO attestation · $MONTH · $START -> $END ==="

# Entries may be newline- or space-separated; a pipe-delimited entry never contains spaces
# inside fields except the label and the dimension filter, so split on newlines first.
while IFS= read -r ENTRY; do
  [[ -z "$ENTRY" ]] && continue
  IFS='|' read -r LABEL TARGET NS METRIC DIM COMP REGION <<<"$ENTRY"
  [[ -n "$LABEL" && "$TARGET" =~ ^[0-9]+$ && -n "$NS" && -n "$METRIC" && -n "$COMP" && -n "$REGION" ]] \
    || { echo "ERROR: malformed DR_RPO_METRICS entry: $ENTRY" >&2; exit 1; }
  MQL="${METRIC}[${RESOLUTION}]${DIM:+{$DIM}}.max()"
  echo "-> $LABEL: $MQL"

  if [[ $DRY_RUN -eq 1 ]]; then
    WG_DRY_RUN=1 wg_oci monitoring metric-data summarize-metrics-data --namespace "$NS" --query-text "$MQL" \
        --start-time "$START" --end-time "$END" --compartment-id "$COMP" --region "$REGION"
    continue
  fi

  J=$(wg_oci monitoring metric-data summarize-metrics-data --namespace "$NS" --query-text "$MQL" \
        --start-time "$START" --end-time "$END" --compartment-id "$COMP" --region "$REGION" 2>/dev/null || echo '{}')
  # Flatten all datapoints across returned series into "timestamp value" lines, sorted.
  DP=$(jq -r '[.data[]?."aggregated-datapoints"[]?] | sort_by(.timestamp)[] | "\(.timestamp) \(.value)"' <<<"$J")
  N=$(grep -c . <<<"$DP" || true)

  if [[ "$N" -eq 0 ]]; then
    NODATA=$((NODATA+1))
    ROWS+=("| $LABEL | ${TARGET}s | **NO DATA** | — | — | — | — | — | Metric \`$NS/$METRIC\` returned no points. Verify the metric name and dimension filter; absence of signal is a finding (docs/04 §2). |")
    continue
  fi

  STATS=$(awk -v t="$TARGET" -v step="$STEP" '
    { v[NR]=$2; ts[NR]=$1; if ($2>t) over++; if ($2>max) max=$2 }
    END {
      n=NR; asort(v);
      p50=v[int(n*0.50)>0?int(n*0.50):1]; p95=v[int(n*0.95)>0?int(n*0.95):1]; p99=v[int(n*0.99)>0?int(n*0.99):1];
      printf "%d %.0f %.0f %.0f %.0f %.2f %.1f", n, p50, p95, p99, max, (over/n)*100, over*step/3600
    }' <<<"$DP")
  read -r COUNT P50 P95 P99 MAX PCT_OUT HRS_OUT <<<"$STATS"

  # Interruptions: gaps between consecutive points larger than 3x the step.
  GAPS=$(awk -v step="$STEP" -v lbl="$LABEL" '
    { cmd="date -u -d \"" $1 "\" +%s"; cmd | getline e; close(cmd);
      if (prev && e-prev > 3*step) printf "| %s | %s | %s | %.1f h | (root cause) | (status) |\n", lbl, pts, $1, (e-prev)/3600;
      prev=e; pts=$1 }' <<<"$DP")
  [[ -n "$GAPS" ]] && while IFS= read -r g; do INTERRUPTIONS+=("$g"); done <<<"$GAPS"

  [[ "$(awk -v p="$PCT_OUT" 'BEGIN{print (p>0)?1:0}')" == "1" ]] && BREACHES=$((BREACHES+1))
  ROWS+=("| $LABEL | ${TARGET}s | $COUNT | ${P50}s | ${P95}s | ${P99}s | ${MAX}s | ${PCT_OUT}% (${HRS_OUT} h) | |")
done <<<"$(printf '%s\n' "$DR_RPO_METRICS")"

[[ $DRY_RUN -eq 1 ]] && exit 0

{
  cat <<HDR
# RPO attestation — ${MONTH}

Generated ${TS} by \`scripts/oci/generate-rpo-attestation.sh\` from OCI Monitoring
(\`summarize-metrics-data\`, resolution ${RESOLUTION}, max() per interval). Method per
\`docs/04-monitoring.md\` §4. Targets per \`docs/02-mtd-tiers.md\` §2.

**Summary:** ${#ROWS[@]} resource(s) assessed · ${BREACHES} with time outside RPO · ${NODATA} with no data.

| Resource | Tier RPO | Samples | p50 | p95 | p99 | Max | Time outside RPO | Exceptions / remediation |
|---|---|---|---|---|---|---|---|---|
HDR
  printf '%s\n' "${ROWS[@]}"
  echo
  echo "## Replication interruptions (data gaps > 3× resolution)"
  echo
  if [[ ${#INTERRUPTIONS[@]} -eq 0 ]]; then echo "None detected at ${RESOLUTION} resolution."; else
    echo "| Resource | Last point before gap | First point after | Duration | Root cause | Remediation status |"
    echo "|---|---|---|---|---|---|"
    printf '%s\n' "${INTERRUPTIONS[@]}"
  fi
  cat <<'FTR'

## Attestation

The figures above are measured, not asserted. Where the tier RPO was exceeded, the root
cause and remediation status must be completed before this report is signed. A
resource showing **NO DATA** is not compliant; it is unmonitored.

| Role | Name | Date | Signature |
|---|---|---|---|
| DBA on-call (Data Guard rows) | | | |
| Infra on-call (storage rows) | | | |
| DR Coordinator | | | |
FTR
} > "$REPORT"

echo "=== Report written to $REPORT ($BREACHES breach(es), $NODATA no-data) ==="
[[ $NODATA -gt 0 ]] && exit 1 || exit 0
