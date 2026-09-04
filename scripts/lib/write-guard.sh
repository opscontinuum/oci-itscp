#!/usr/bin/env bash
# write-guard.sh — structural enforcement that only sanctioned mutations reach OCI.
#
# The mirror image of the read-only guard used by discovery tooling. Discovery
# must never write; these scripts must write, but only the specific things the
# runbooks in this repository actually ask for.
#
# Source this file and call the OCI CLI ONLY through wg_oci(). The guard splits
# the command into its positional path (everything before the first flag),
# classifies it, and refuses anything it does not recognise.
#
#   source "$(dirname "$0")/../lib/write-guard.sh"
#   wg_oci bv volume-group-replica get --volume-group-replica-id "$R"   # read, runs
#   wg_oci compute instance action --action STOP --instance-id "$I"     # reversible, runs
#   wg_oci fs replication delete --replication-id "$R"                  # one-way, needs
#                                                                       # WG_CONFIRM + WG_TICKET
#   wg_oci db autonomous-database delete --autonomous-database-id "$D"  # refused, exit 3
#
# It FAILS CLOSED. The mutating allowlist is an ALLOWLIST, not a denylist: a
# service that ships a novel destructive verb tomorrow is refused by default
# rather than discovered in production. Widening it is a deliberate edit with a
# runbook citation, reviewed like any other change to the recovery plan.
#
# Self-test:  bash scripts/lib/write-guard.sh --self-test
#
# Exit codes (see scripts/README.md for the repository-wide convention):
#   0  the call ran, or was printed under WG_DRY_RUN
#   3  REFUSED — not on the allowlist, or missing --confirm / --ticket
#
# Deliberately NOT set -e: this file is sourced by scripts that choose their own
# error mode (the forensic and reporting scripts run with `set -uo pipefail` so a
# single unreadable resource does not abort the walk).
set -o pipefail

# ---------------------------------------------------------------------------
# 1. Reads
# ---------------------------------------------------------------------------
# An OCI operation is a read if and only if its verb begins with "list" or
# "get" — list, list-replication-policies, get, get-replication-policy. Reads
# need no authorisation: nothing in this repository is protected by hiding it.
readonly WG_READ_PATTERN='^(list|get)(-[a-z0-9-]+)?$'

# Reads whose verb does not fit that shape. Each one is a POST that returns data
# and changes nothing. Explicit, because "it looks harmless" is not a control.
readonly WG_READ_EXEMPT='
monitoring metric-data summarize-metrics-data
'

# ---------------------------------------------------------------------------
# 2. The mutating allowlist
# ---------------------------------------------------------------------------
# Derived from the operations the scripts in scripts/oci/ and the runbooks in
# runbooks/ genuinely invoke — nothing was added on the grounds that it might be
# wanted later. Format:
#
#   <positional command path>|<class>|<caller>|<runbook citation>
#
# Class ONE_WAY   — irreversible, or reversible only through a full baseline
#                   copy or a rebuild. Requires WG_CONFIRM=1 and WG_TICKET.
# Class REVERSIBLE— compute, steering and evidence operations that can be put
#                   back the way they were. No confirmation gate; the calling
#                   script's own guard rails (OCPU floor, backend-set health,
#                   posture reason) still apply, and the guard notes the call
#                   when no ticket or reason accompanies it.
#
# The governing rule of this plan is "tear down compute, never tear down
# replication" (README, docs/03-replication-matrix.md §3). That is why every
# operation which removes a replication relationship is ONE_WAY even where the
# OCI API considers it routine.
WG_MUTATING_ALLOWLIST=(
  # --- Storage failover: the one-way doors of RB-01 §3 and RB-02 §4 ----------
  "bv volume-group create|ONE_WAY|activate-volume-group.sh|RB-01 §3, RB-02 §4 — activates a volume group replica; consumes the replica's sync point"
  "fs replication delete|ONE_WAY|fss-failover.sh, decommission-dr.sh|RB-01 §3, RB-02 §4, RB-05 §5 step 4 — exported FSS targets cannot be reused"
  "os replication make-bucket-writable|ONE_WAY|objectstore-failover.sh|RB-02 §4 — destination-side break of the replication policy"
  "os replication delete-replication-policy|ONE_WAY|objectstore-failover.sh, decommission-dr.sh|RB-02 §4, RB-05 §5 step 4 — a new policy does not backfill existing objects"

  # --- Posture and readiness: reversible by construction --------------------
  "db cloud-vm-cluster update|REVERSIBLE|set-dr-posture.sh, scale-exadata-ocpu.sh|RB-01 §3, RB-05 §1 — online OCPU scaling; the OCPU floor guard sits in the caller"
  "compute instance action|REVERSIBLE|set-dr-posture.sh|RB-04 §2, RB-05 §1 — START/STOP of the pilot-light Windows tiers"
  "dns steering-policy update|REVERSIBLE|steer-traffic.sh|RB-01 §3 step 5, RB-02 §2 — enable/disable a FAILOVER answer"
  "os object put|REVERSIBLE|decommission-dr.sh|RB-05 §5 step 8 — uploads the evidence archive; adds an object, removes nothing"

  # --- Decommission: RB-05 §5, sign-off gated in the caller -----------------
  "disaster-recovery dr-plan delete|ONE_WAY|decommission-dr.sh|RB-05 §5 step 1"
  "disaster-recovery dr-protection-group disassociate|ONE_WAY|decommission-dr.sh|RB-05 §5 step 1 — a DRPG must be disassociated before deletion"
  "disaster-recovery dr-protection-group delete|ONE_WAY|decommission-dr.sh|RB-05 §5 step 1"
  "dns steering-policy-attachment delete|ONE_WAY|decommission-dr.sh|RB-05 §5 step 2"
  "dns steering-policy delete|ONE_WAY|decommission-dr.sh|RB-05 §5 step 2"
  "health-checks http-monitor delete|ONE_WAY|decommission-dr.sh|RB-05 §5 step 2"
  "compute instance terminate|ONE_WAY|decommission-dr.sh|RB-05 §5 step 3"
  "bv volume-group delete|ONE_WAY|decommission-dr.sh|RB-05 §5 step 3"
  "lb load-balancer delete|ONE_WAY|decommission-dr.sh|RB-05 §5 step 3"
  "bv volume-group update|ONE_WAY|decommission-dr.sh|RB-05 §5 step 4 — clearing --volume-group-replicas deletes the Phoenix replica"
  "db database delete|ONE_WAY|decommission-dr.sh|RB-05 §5 step 5 — removes the Phoenix standby from the Data Guard configuration"
  "db cloud-vm-cluster delete|ONE_WAY|decommission-dr.sh|RB-05 §5 step 7"
  "db cloud-exa-infra delete|ONE_WAY|decommission-dr.sh|RB-05 §5 step 7"
)

# Operations the runbooks direct an operator to type by hand and that no script
# in this repository issues. They are deliberately ABSENT from the allowlist
# above: the guard governs what the automation may do, and granting capability
# that nothing exercises is capability nobody has tested. If one of these is
# ever promoted into a script, add it here with its citation, add a dry-run
# assertion, and say so in the change record.
#
#   db database switch-over-data-guard        RB-01 §3 (control-plane switchover)
#   db database reinstate-data-guard          RB-03 §3 (reinstate the old primary)
#   db database convert-standby-database-type RB-04 §2 (snapshot standby for a drill)
#   db database create-standby-database       RB-05 §2 (rebuild the standby)
#   lb backend update                         scripts/windows/Stop-EBSAppTier.ps1 (PowerShell)
#
# ---------------------------------------------------------------------------
# 3. Caller-supplied state
# ---------------------------------------------------------------------------
WG_DRY_RUN="${WG_DRY_RUN:-0}"   # 1 = print the command, execute nothing
WG_CONFIRM="${WG_CONFIRM:-0}"   # 1 = the operator passed --confirm / --confirm-unprotected
WG_TICKET="${WG_TICKET:-}"      # change reference, from --ticket
WG_REASON="${WG_REASON:-}"      # free text, from --reason
WG_APPROVER="${WG_APPROVER:-}"  # from --approver, recorded only
WG_TIMEOUT="${WG_TIMEOUT:-}"    # optional seconds; wraps the call in timeout(1)

# wg_authorise <confirm 0|1> <ticket> [reason] [approver]
wg_authorise() {
  WG_CONFIRM="${1:-0}"
  WG_TICKET="${2:-}"
  WG_REASON="${3:-}"
  WG_APPROVER="${4:-}"
}

# Counters live in files, not variables. wg_oci is routinely called inside a
# command substitution, and a variable incremented in a subshell never reaches
# the parent. A guard whose refusal count is silently lost is not a guard.
WG_STATE_DIR="${WG_STATE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/wgguard.XXXXXX")}"
: > "$WG_STATE_DIR/made"
: > "$WG_STATE_DIR/refused"

wg_count()   { printf 'x' >> "$WG_STATE_DIR/$1"; }
wg_made()    { wc -c < "$WG_STATE_DIR/made" | tr -d ' '; }
wg_refused() { wc -c < "$WG_STATE_DIR/refused" | tr -d ' '; }

# ---------------------------------------------------------------------------
# 4. Classification
# ---------------------------------------------------------------------------

# wg_command_path ARGS... -> the positional tokens before the first flag,
# space-joined. "bv volume-group-replica get --volume-group-replica-id X"
# yields "bv volume-group-replica get".
wg_command_path() {
  local out="" tok
  for tok in "$@"; do
    case "$tok" in
      -*) break ;;
      *)  out="${out:+$out }$tok" ;;
    esac
  done
  printf '%s' "$out"
}

# wg_allowlist_entry PATH -> the matching allowlist line, or empty.
wg_allowlist_entry() {
  local path="$1" entry
  for entry in "${WG_MUTATING_ALLOWLIST[@]}"; do
    [[ "${entry%%|*}" == "$path" ]] && { printf '%s' "$entry"; return 0; }
  done
  return 1
}

# wg_classify PATH -> READ | ONE_WAY | REVERSIBLE | UNKNOWN
wg_classify() {
  local path="$1" entry verb
  [[ -z "$path" ]] && { printf 'UNKNOWN'; return; }

  # Mutating allowlist first, so an operation can never be waved through on the
  # shape of its verb alone.
  if entry="$(wg_allowlist_entry "$path")"; then
    entry="${entry#*|}"
    printf '%s' "${entry%%|*}"
    return
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" == "$path" ]] && { printf 'READ'; return; }
  done <<< "$WG_READ_EXEMPT"

  verb="${path##* }"
  if printf '%s' "$verb" | grep -Eq "$WG_READ_PATTERN"; then
    printf 'READ'
    return
  fi

  printf 'UNKNOWN'
}

# ---------------------------------------------------------------------------
# 5. The guard
# ---------------------------------------------------------------------------

wg_refuse() {
  wg_count refused
  printf 'WRITE GUARD: %s\n' "$1" >&2
  shift
  local line
  for line in "$@"; do printf '  %s\n' "$line" >&2; done
  return 3
}

wg_oci() {
  local path class entry
  path="$(wg_command_path "$@")"
  class="$(wg_classify "$path")"

  case "$class" in
    UNKNOWN)
      wg_refuse "refused unrecognised operation \"${path:-<none>}\"" \
        "full command: oci $*" \
        "This operation is on neither the read shape (list*/get*) nor the mutating" \
        "allowlist in scripts/lib/write-guard.sh. The guard fails closed: it will not" \
        "let a call it has never seen reach a tenancy. If the runbooks genuinely need" \
        "it, add it to WG_MUTATING_ALLOWLIST with its class and its runbook citation," \
        "and add a dry-run assertion in scripts/test-scripts.sh."
      return 3
      ;;
    ONE_WAY)
      entry="$(wg_allowlist_entry "$path")"
      if [[ "$WG_CONFIRM" != "1" ]]; then
        wg_refuse "refused one-way-door operation \"$path\" without confirmation" \
          "full command: oci $*" \
          "provenance: ${entry##*|}" \
          "Completing this destroys a replication relationship or a resource that" \
          "cannot be put back incrementally. Re-run with --confirm (or, for" \
          "decommission-dr.sh, --confirm-unprotected) once RB-01, RB-02 or RB-05" \
          "genuinely applies."
        return 3
      fi
      if [[ -z "$WG_TICKET" ]]; then
        wg_refuse "refused one-way-door operation \"$path\" without a change reference" \
          "full command: oci $*" \
          "provenance: ${entry##*|}" \
          "Every irreversible action in this plan is auditable: evidence/ records" \
          "who did what, under which change. Re-run with --ticket \"<change-ref>\"."
        return 3
      fi
      ;;
    REVERSIBLE)
      # Once per run, not once per call: a warm posture stops every application
      # node, and a note repeated per instance is a note nobody reads.
      if [[ -z "$WG_TICKET" && -z "$WG_REASON" && ! -e "$WG_STATE_DIR/noted" ]]; then
        : > "$WG_STATE_DIR/noted"
        printf 'WRITE GUARD: note - reversible operations are running with no --ticket and no --reason.\n' >&2
        printf '  The evidence log will record the operator and the timestamp only.\n' >&2
      fi
      ;;
  esac

  if [[ "$WG_DRY_RUN" = "1" ]]; then
    # stderr, not stdout: callers capture stdout, and a dry run whose command
    # list is swallowed by a command substitution shows nothing.
    printf '    oci %s\n' "$*" >&2
    wg_count made
    return 0
  fi

  # Mutating calls announce themselves, exactly as the scripts did before the
  # guard existed. Reads stay quiet: the forensic and reporting scripts issue
  # dozens of them and their output is the report, not the call list.
  if [[ "$class" != "READ" ]]; then printf '  + oci %s\n' "$*"; fi

  wg_count made
  if [[ -n "$WG_TIMEOUT" ]] && command -v timeout >/dev/null 2>&1; then
    command timeout "$WG_TIMEOUT" oci "$@"
  else
    command oci "$@"
  fi
}

# wg_allowlist_table — the allowlist as a Markdown table, for scripts/README.md.
wg_allowlist_table() {
  local entry path class caller why
  printf '| Operation | Class | Called by | Why it is needed |\n|---|---|---|---|\n'
  for entry in "${WG_MUTATING_ALLOWLIST[@]}"; do
    path="${entry%%|*}"; entry="${entry#*|}"
    class="${entry%%|*}"; entry="${entry#*|}"
    caller="${entry%%|*}"; why="${entry#*|}"
    printf '| `oci %s` | %s | `%s` | %s |\n' "$path" "$class" "$caller" "$why"
  done
}

# ---------------------------------------------------------------------------
# 6. Self-test
# ---------------------------------------------------------------------------

wg_self_test() {
  local fails=0 rc
  printf 'write-guard self-test\n\n'

  _wg_expect() {
    # _wg_expect <expected-rc> <label> -- ARGS...
    local want="$1" label="$2"; shift 3
    WG_DRY_RUN=1 wg_oci "$@" >/dev/null 2>&1; rc=$?
    if [[ $rc -eq $want ]]; then
      printf '  ok    %s: oci %s\n' "$label" "$*"
    else
      printf '  FAIL  %s (rc=%s, wanted %s): oci %s\n' "$label" "$rc" "$want" "$*"
      fails=$((fails + 1))
    fi
  }

  printf '  reads need no authorisation\n'
  wg_authorise 0 ""
  _wg_expect 0 'allow read' -- bv volume-group-replica get --volume-group-replica-id ocid1.test
  _wg_expect 0 'allow read' -- fs replication get --replication-id ocid1.test
  _wg_expect 0 'allow read' -- os replication get-replication-policy --bucket-name b
  _wg_expect 0 'allow read' -- disaster-recovery dr-plan list --dr-protection-group-id ocid1.test
  _wg_expect 0 'allow read' -- network nsg rules list --nsg-id ocid1.test
  _wg_expect 0 'allow read' -- monitoring metric-data summarize-metrics-data --namespace n

  printf '\n  reversible mutations need no confirmation\n'
  _wg_expect 0 'allow reversible' -- compute instance action --action STOP --instance-id ocid1.test
  _wg_expect 0 'allow reversible' -- db cloud-vm-cluster update --cpu-core-count 4
  _wg_expect 0 'allow reversible' -- dns steering-policy update --steering-policy-id ocid1.test
  _wg_expect 0 'allow reversible' -- os object put --bucket-name b --name evidence.tar.gz

  printf '\n  one-way doors are refused without --confirm\n'
  _wg_expect 3 'refuse unconfirmed' -- fs replication delete --replication-id ocid1.test
  _wg_expect 3 'refuse unconfirmed' -- os replication make-bucket-writable --bucket-name b
  _wg_expect 3 'refuse unconfirmed' -- bv volume-group create --display-name vg
  _wg_expect 3 'refuse unconfirmed' -- compute instance terminate --instance-id ocid1.test
  _wg_expect 3 'refuse unconfirmed' -- db database delete --database-id ocid1.test

  printf '\n  one-way doors are refused with --confirm but no --ticket\n'
  wg_authorise 1 ""
  _wg_expect 3 'refuse ticketless' -- fs replication delete --replication-id ocid1.test
  _wg_expect 3 'refuse ticketless' -- bv volume-group update --volume-group-id ocid1.test
  _wg_expect 3 'refuse ticketless' -- db cloud-exa-infra delete --cloud-exa-infra-id ocid1.test

  printf '\n  one-way doors run with --confirm and --ticket\n'
  wg_authorise 1 "CHG0000000"
  _wg_expect 0 'allow confirmed' -- fs replication delete --replication-id ocid1.test
  _wg_expect 0 'allow confirmed' -- os replication delete-replication-policy --bucket-name b
  _wg_expect 0 'allow confirmed' -- disaster-recovery dr-protection-group disassociate --type DEFAULT
  _wg_expect 0 'allow confirmed' -- lb load-balancer delete --load-balancer-id ocid1.test

  printf '\n  operations outside the allowlist are refused even fully authorised\n'
  _wg_expect 3 'refuse novel' -- db autonomous-database delete --autonomous-database-id ocid1.test
  _wg_expect 3 'refuse novel' -- recovery protected-database delete --protected-database-id ocid1.test
  _wg_expect 3 'refuse novel' -- os bucket delete --bucket-name b
  _wg_expect 3 'refuse novel' -- db database failover --database-id ocid1.test
  _wg_expect 3 'refuse novel' -- db database switch-over-data-guard --database-id ocid1.test
  _wg_expect 3 'refuse novel' -- bv volume-group-replica delete --volume-group-replica-id ocid1.test
  _wg_expect 3 'refuse novel' -- network vcn delete --vcn-id ocid1.test
  _wg_expect 3 'refuse novel' -- iam policy create --name p
  _wg_expect 3 'refuse no operation' -- --help

  printf '\n  the guard counts what it did\n'
  if [[ "$(wg_refused)" -gt 0 && "$(wg_made)" -gt 0 ]]; then
    printf '  ok    %s call(s) allowed, %s refused\n' "$(wg_made)" "$(wg_refused)"
  else
    printf '  FAIL  counters not recorded (made=%s refused=%s)\n' "$(wg_made)" "$(wg_refused)"
    fails=$((fails + 1))
  fi

  printf '\n'
  if [[ $fails -eq 0 ]]; then
    printf 'all write-guard tests passed\n'; return 0
  else
    printf '%s write-guard test(s) FAILED\n' "$fails"; return 1
  fi
}

# Only when executed directly. A sourcing script may legitimately be called with
# --self-test or --allowlist-table of its own, and the guard must not swallow it.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test)       wg_self_test; exit $? ;;
    --allowlist-table) wg_allowlist_table; exit 0 ;;
  esac
fi
