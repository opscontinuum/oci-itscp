#!/usr/bin/env bash
# test-scripts.sh — proves the scripts in this repository cannot mutate anything
# the runbooks did not ask for.
#
# The Terraform has three tiers of proof and the scripts had none, which is the
# wrong way round: the Terraform is apply-locked and was never applied, and these
# scripts delete replication relationships that take hours to rebuild.
#
# Five checks. Any one failing fails the suite:
#   1. shellcheck, when it is installed (guarded, not required).
#   2. The write guard refuses what the design says it refuses (unit).
#   3. No script calls the OCI CLI outside the guard (static tripwire).
#   4. Every command a full dry run would issue is on the allowlist, and nothing
#      executes (end to end).
#   5. Every scripts/ invocation written in a runbook names flags that script
#      accepts.
#
# Check 3 is the one that matters over time. The guard is only protective if
# every call goes through it, and a future edit that adds a direct `oci` call
# would bypass it silently. This fails CI instead.
#
# Runs entirely offline. It reaches no tenancy, needs no credentials, and
# proves it: a poisoned `oci` on PATH records any execution and fails the suite.
#
# Usage: ./scripts/test-scripts.sh

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd .. && pwd)"

FAILS=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }
skip() { printf '  skip  %s\n' "$1"; }

# --- fixture ---------------------------------------------------------------
# A resource inventory of placeholders. No OCIDs, hostnames or names from any
# real tenancy appear here, and terraform/dr-resources.env is never created.
FIX="$(mktemp -d "${TMPDIR:-/tmp}/itscp-tests.XXXXXX")"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/bin" "$FIX/evidence" "$FIX/out"

cat > "$FIX/dr-resources.env" <<'ENV'
PRIMARY_REGION="us-ashburn-1"
DR_REGION="us-phoenix-1"
DR_COMPARTMENT_OCID="ocid1.compartment.oc1..placeholder"
PRIMARY_COMPARTMENT_OCID="ocid1.compartment.oc1..placeholder"
DR_OS_NAMESPACE="placeholdernamespace"
DR_VMCLUSTER_OCID="ocid1.cloudvmcluster.oc1.phx.placeholder"
PRIMARY_VMCLUSTER_OCID="ocid1.cloudvmcluster.oc1.iad.placeholder"
DR_VMCLUSTER_NODE_COUNT=2
PRIMARY_VMCLUSTER_NODE_COUNT=2
DR_OCPU_FLOOR=4
DR_OCPU_PRODUCTION=32
PRIMARY_OCPU_FLOOR=4
DR_APP_INSTANCE_OCIDS="ocid1.instance.oc1.phx.placeholder1 ocid1.instance.oc1.phx.placeholder2"
DR_DRILL_INSTANCE_OCIDS="ocid1.instance.oc1.phx.placeholderdrill"
DR_STEERING_POLICY_OCID="ocid1.dnssteeringpolicy.oc1..placeholder"
DR_STEERING_ANSWER_IAD="primary-region-answer"
DR_STEERING_ANSWER_PHX="dr-region-answer"
DR_LB_OCID="ocid1.loadbalancer.oc1.phx.placeholder"
DR_LB_BACKENDSET="placeholder-backendset"
PRIMARY_LB_OCID="ocid1.loadbalancer.oc1.iad.placeholder"
PRIMARY_LB_BACKENDSET="placeholder-backendset"
DR_VOLUME_GROUP_REPLICA_OCIDS="ocid1.volumegroupreplica.oc1.phx.placeholder"
PRIMARY_VOLUME_GROUP_OCIDS="ocid1.volumegroup.oc1.iad.placeholder"
DR_ACTIVATED_VOLUME_GROUP_OCIDS="ocid1.volumegroup.oc1.phx.placeholder"
DR_FSS_REPLICATION_OCIDS="ocid1.filesystemreplication.oc1.phx.placeholder"
DR_BUCKET_POLICIES="placeholder-bucket:ocid1.replicationpolicy.oc1..placeholder"
DR_FSDR_DRPG_OCIDS="ocid1.drprotectiongroup.oc1.phx.placeholder"
DR_HEALTH_CHECK_OCIDS="ocid1.httpmonitor.oc1..placeholder"
DR_STANDBY_DATABASE_OCID="ocid1.database.oc1.phx.placeholder"
DR_PROTECTED_DB_OCIDS="ocid1.protecteddatabase.oc1.iad.placeholder"
DR_EXA_INFRA_OCID="ocid1.cloudexadatainfrastructure.oc1.phx.placeholder"
DR_EVIDENCE_ARCHIVE_BUCKET="placeholder-evidence-bucket"
DR_RPO_METRICS="Placeholder standby apply lag|30|oracle_oci_database|ApplyLag||ocid1.compartment.oc1..placeholder|us-phoenix-1"
DG_PRIMARY="EBSPROD_IAD"
DG_STANDBY_LOCAL="EBSPROD_IAD2"
DG_STANDBY_REMOTE="EBSPROD_PHX"
ENV

# A poisoned OCI CLI. If any script reaches it, the marker file appears and
# check 4 fails. Nothing here can talk to a tenancy even if it wanted to.
cat > "$FIX/bin/oci" <<'SHIM'
#!/usr/bin/env bash
printf 'oci %s\n' "$*" >> "$OCI_EXECUTED_MARKER"
exit 42
SHIM
chmod +x "$FIX/bin/oci"

export PATH="$FIX/bin:$PATH"
export OCI_EXECUTED_MARKER="$FIX/EXECUTED"
export DR_CONFIG="$FIX/dr-resources.env"
export DR_EVIDENCE_DIR="$FIX/evidence"

EVIDENCE_BEFORE="$(ls -A "$REPO_ROOT/evidence" 2>/dev/null | sort | tr '\n' ' ')"

# --- 1. shellcheck ---------------------------------------------------------
printf '\n1. shellcheck\n'
if command -v shellcheck >/dev/null 2>&1; then
    SC_OUT="$(shellcheck -x -S warning lib/*.sh oci/*.sh dataguard/*.sh test-scripts.sh 2>&1)"
    if [ -z "$SC_OUT" ]; then
        pass 'shellcheck clean at severity warning and above'
    else
        fail 'shellcheck findings:'
        printf '%s\n' "$SC_OUT" | sed 's/^/          /'
    fi
else
    skip 'shellcheck is not installed; static analysis was not run'
    printf '        install it (https://www.shellcheck.net) to run this check locally.\n'
    printf '        The remaining four checks do not depend on it.\n'
fi

# --- 2. guard unit tests ---------------------------------------------------
printf '\n2. write-guard unit tests\n'
if bash lib/write-guard.sh --self-test >/dev/null 2>&1; then
    pass 'the guard allows reads, gates one-way doors, and refuses the unknown'
else
    fail 'guard self-test failed - run: bash scripts/lib/write-guard.sh --self-test'
fi

# --- 3. static tripwire ----------------------------------------------------
printf '\n3. static tripwire: no OCI CLI calls outside the guard\n'
# `command oci` inside lib/write-guard.sh is the single sanctioned call site. Three
# exclusions: this file necessarily mentions the string it looks for; comment lines
# describe calls rather than making them; and the read-only scripts each grep their
# own source for a forbidden verb, so the pattern appears as a literal inside a
# `grep -qE`, not as an invocation.
STRAY="$(grep -rnE '(^|[^_a-zA-Z-])oci ' --include='*.sh' . 2>/dev/null \
        | grep -v '^\./lib/write-guard\.sh:' \
        | grep -v '^\./test-scripts\.sh:' \
        | grep -v 'wg_oci' \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
        | grep -v 'grep -qE' \
        || true)"
if [ -z "$STRAY" ]; then
    pass 'every OCI invocation goes through wg_oci'
else
    fail 'OCI CLI invoked outside the guard:'
    printf '%s\n' "$STRAY" | sed 's/^/          /'
fi

# The PowerShell tier is outside the guard's reach and is recorded, not hidden.
PS_OCI="$(grep -rlE '(^|[^_a-zA-Z-])oci ' --include='*.ps1' . 2>/dev/null || true)"
if [ -n "$PS_OCI" ]; then
    printf '        note: PowerShell scripts call the OCI CLI directly (documented in scripts/README.md §1):\n'
    printf '%s\n' "$PS_OCI" | sed 's/^/          /'
fi

# --- 4. dry-run end to end -------------------------------------------------
printf '\n4. end to end: every dry-run command is on the allowlist, and nothing runs\n'

# shellcheck source=lib/write-guard.sh
source lib/write-guard.sh

# Every script that mutates, plus the read-only walkers, in the shapes the
# runbooks use. check-replication-health.sh has no --dry-run to exercise: it
# only reads, and there is no walk to preview.
run_dry() {
    local label="$1"; shift
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [ $rc -ne 0 ]; then
        fail "$label exited $rc under --dry-run"
        printf '%s\n' "$out" | tail -5 | sed 's/^/          /'
        return
    fi
    printf '%s\n' "$out" | grep -E '^[[:space:]]+oci ' >> "$FIX/emitted" || true
}

run_dry 'set-dr-posture warm'      ./oci/set-dr-posture.sh --posture warm --dry-run
run_dry 'set-dr-posture hot'       ./oci/set-dr-posture.sh --posture hot --reason "suite" --dry-run
run_dry 'set-dr-posture drill'     ./oci/set-dr-posture.sh --posture drill --reason "suite" --dry-run
run_dry 'scale-exadata up'         ./oci/scale-exadata-ocpu.sh --cluster EBSPROD_PHX --ocpu-per-node 16 --dry-run
run_dry 'scale-exadata to floor'   ./oci/scale-exadata-ocpu.sh --cluster EBSPROD_PHX --total-ocpu 4 --reason "suite" --dry-run
run_dry 'scale-exadata primary'    ./oci/scale-exadata-ocpu.sh --cluster EBSPROD_IAD --total-ocpu 8 --dry-run
run_dry 'steer-traffic phoenix'    ./oci/steer-traffic.sh --target phoenix --dry-run
run_dry 'steer-traffic ashburn'    ./oci/steer-traffic.sh --target ashburn --dry-run
run_dry 'steer-traffic auto'       ./oci/steer-traffic.sh --target auto --dry-run
run_dry 'activate-volume-group'    ./oci/activate-volume-group.sh --confirm --ticket "TEST-0000" --dry-run
run_dry 'fss-failover'             ./oci/fss-failover.sh --confirm --ticket "TEST-0000" --dry-run
run_dry 'fss-failover lossless'    ./oci/fss-failover.sh --confirm --ticket "TEST-0000" --lossless --dry-run
run_dry 'objectstore-failover'     ./oci/objectstore-failover.sh --bucket placeholder-bucket-dr \
                                       --source-bucket placeholder-bucket \
                                       --policy ocid1.replicationpolicy.oc1..placeholder \
                                       --confirm --ticket "TEST-0000" --dry-run
run_dry 'decommission-dr'          ./oci/decommission-dr.sh --confirm-unprotected \
                                       --approver "Placeholder Approver" --ticket "TEST-0000" --dry-run
run_dry 'capture-replication-state' ./oci/capture-replication-state.sh --out "$FIX/out/state.md" --dry-run
run_dry 'detect-drift'             ./oci/detect-drift.sh --report "$FIX/out/drift.md" --dry-run
run_dry 'generate-rpo-attestation' ./oci/generate-rpo-attestation.sh --month 2026-08 --out "$FIX/out" --dry-run

COUNT="$(grep -c 'oci ' "$FIX/emitted" 2>/dev/null || echo 0)"
if [ "$COUNT" -lt 25 ]; then
    fail "dry runs emitted only $COUNT commands; expected the full set"
else
    pass "$COUNT commands emitted across every dry-run path"
fi

BAD=0
UNSEEN=0
while IFS= read -r line; do
    [ -n "$line" ] || continue
    # Strip the guard's indent and the leading "oci", then classify the command
    # path with the guard's own classifier. The test cannot drift from the guard.
    # shellcheck disable=SC2086
    set -- ${line#*oci }
    path="$(wg_command_path "$@")"
    class="$(wg_classify "$path")"
    case "$class" in
        READ|REVERSIBLE|ONE_WAY) ;;
        *) printf '          off-allowlist operation "%s" in: %s\n' "$path" "$line"; BAD=$((BAD + 1)) ;;
    esac
done < "$FIX/emitted"
if [ "$BAD" -eq 0 ]; then
    pass 'every emitted operation is a read or on the mutating allowlist'
else
    fail "$BAD emitted operation(s) are outside the allowlist"
fi

# Every ONE_WAY entry on the allowlist should be reachable from some dry run.
# An entry nothing exercises is capability nobody has tested.
for entry in "${WG_MUTATING_ALLOWLIST[@]}"; do
    p="${entry%%|*}"
    grep -qE "^[[:space:]]+oci ${p}( |$)" "$FIX/emitted" || {
        printf '          allowlist entry never exercised: oci %s\n' "$p"
        UNSEEN=$((UNSEEN + 1))
    }
done
if [ "$UNSEEN" -eq 0 ]; then
    pass 'every allowlist entry is exercised by a dry run'
else
    fail "$UNSEEN allowlist entr(y/ies) exercised by nothing"
fi

if [ -e "$OCI_EXECUTED_MARKER" ]; then
    fail 'the OCI CLI was executed during a dry run:'
    sed 's/^/          /' "$OCI_EXECUTED_MARKER"
else
    pass 'the OCI CLI was never executed; no credentials were needed or used'
fi

EVIDENCE_AFTER="$(ls -A "$REPO_ROOT/evidence" 2>/dev/null | sort | tr '\n' ' ')"
if [ "$EVIDENCE_BEFORE" = "$EVIDENCE_AFTER" ] && [ -z "$(ls -A "$FIX/evidence")" ]; then
    pass 'no evidence record was written by a dry run'
else
    fail 'a dry run wrote an evidence record'
fi

# The one-way doors still refuse without their authorisation, dry run or not.
REFUSED_OK=1
for args in "--dry-run" "--confirm --dry-run"; do
    # shellcheck disable=SC2086
    ./oci/fss-failover.sh $args >/dev/null 2>&1
    [ $? -eq 3 ] || REFUSED_OK=0
done
if [ "$REFUSED_OK" -eq 1 ]; then
    pass 'one-way doors refuse with exit 3 without --confirm and --ticket'
else
    fail 'a one-way door did not refuse without --confirm and --ticket'
fi

# --- 5. runbook invocations ------------------------------------------------
printf '\n5. every runbook invocation names flags the script accepts\n'
BADFLAG=0
CHECKED=0
while IFS= read -r line; do
    script="$(printf '%s' "$line" | grep -oE 'scripts/[a-z]+/[A-Za-z0-9._-]+\.sh' | head -1)"
    [ -n "$script" ] || continue
    if [ ! -f "$REPO_ROOT/$script" ]; then
        printf '          runbook names a script that does not exist: %s\n' "$script"
        BADFLAG=$((BADFLAG + 1)); continue
    fi
    CHECKED=$((CHECKED + 1))
    for flag in $(printf '%s' "$line" | grep -oE '(^| )--[a-z][a-z-]*' | tr -d ' '); do
        grep -qE "[[:space:]|(]${flag}\)" "$REPO_ROOT/$script" || {
            printf '          %s does not accept %s\n' "$script" "$flag"
            BADFLAG=$((BADFLAG + 1))
        }
    done
done < <(
    for f in "$REPO_ROOT"/runbooks/*.md "$REPO_ROOT"/docs/*.md "$REPO_ROOT"/README.md; do
        # Join backslash continuations so a wrapped invocation is read as one command.
        sed -e :a -e '/\\$/N; s/\\\n//; ta' "$f"
    done | grep -E '(\./)?scripts/[a-z]+/[A-Za-z0-9._-]+\.sh'
)
if [ "$BADFLAG" -eq 0 ]; then
    pass "$CHECKED documented invocation(s) parse against their script"
else
    fail "$BADFLAG documented invocation(s) name a flag or script that does not exist"
fi

# --- verdict ---------------------------------------------------------------
printf '\n'
if [ "$FAILS" -eq 0 ]; then
    printf 'PASS - the scripts can only issue operations the runbooks asked for\n'; exit 0
else
    printf 'FAIL - %s check(s) failed\n' "$FAILS"; exit 1
fi
