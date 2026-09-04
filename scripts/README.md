# `scripts/` — the command-line contract

Every script here is something an operator runs during, or in preparation for, an
outage. That is the reason for the rules below: a runbook step that behaves
differently from the step above it is a step someone gets wrong at 03:00.

This file is the single place the contract is written down. If you add a script,
match it.

---

## 1. The write guard

`lib/write-guard.sh` is the one place the OCI CLI is invoked from. Every script in
`oci/` sources it and calls `wg_oci` instead of `oci`. The guard classifies the
command by its positional path and **fails closed**:

| Classification | Rule |
|---|---|
| **Read** | Verb begins with `list` or `get`, or the command appears in the small explicit list of reads whose verb does not fit that shape. Runs with no further gate. |
| **Reversible mutation** | On the allowlist, class `REVERSIBLE`. Runs. The calling script's own guard rails still apply. |
| **One-way door** | On the allowlist, class `ONE_WAY`. Requires `--confirm` (or `--confirm-unprotected`) **and** `--ticket`. |
| **Anything else** | Refused with exit 3 before it reaches the CLI. |

The last row is the point. It is an allowlist, not a denylist: a service that ships
a novel destructive verb tomorrow is refused by default rather than discovered in
production. Widening it is a deliberate edit reviewed alongside the runbook that
needs it.

```bash
bash scripts/lib/write-guard.sh --self-test        # unit tests for the guard
bash scripts/lib/write-guard.sh --allowlist-table  # the table below, regenerated
./scripts/test-scripts.sh                          # the whole suite
```

### The allowlist

Derived from the operations the scripts in `oci/` genuinely issue. Nothing was
added on the grounds that it might be wanted later.

| Operation | Class | Called by | Why it is needed |
|---|---|---|---|
| `oci bv volume-group create` | ONE_WAY | `activate-volume-group.sh` | RB-01 §3, RB-02 §4 — activates a volume group replica; consumes the replica's sync point |
| `oci fs replication delete` | ONE_WAY | `fss-failover.sh, decommission-dr.sh` | RB-01 §3, RB-02 §4, RB-05 §5 step 4 — exported FSS targets cannot be reused |
| `oci os replication make-bucket-writable` | ONE_WAY | `objectstore-failover.sh` | RB-02 §4 — destination-side break of the replication policy |
| `oci os replication delete-replication-policy` | ONE_WAY | `objectstore-failover.sh, decommission-dr.sh` | RB-02 §4, RB-05 §5 step 4 — a new policy does not backfill existing objects |
| `oci db cloud-vm-cluster update` | REVERSIBLE | `set-dr-posture.sh, scale-exadata-ocpu.sh` | RB-01 §3, RB-05 §1 — online OCPU scaling; the OCPU floor guard sits in the caller |
| `oci compute instance action` | REVERSIBLE | `set-dr-posture.sh` | RB-04 §2, RB-05 §1 — START/STOP of the pilot-light Windows tiers |
| `oci dns steering-policy update` | REVERSIBLE | `steer-traffic.sh` | RB-01 §3 step 5, RB-02 §2 — enable/disable a FAILOVER answer |
| `oci os object put` | REVERSIBLE | `decommission-dr.sh` | RB-05 §5 step 8 — uploads the evidence archive; adds an object, removes nothing |
| `oci disaster-recovery dr-plan delete` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 1 |
| `oci disaster-recovery dr-protection-group disassociate` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 1 — a DRPG must be disassociated before deletion |
| `oci disaster-recovery dr-protection-group delete` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 1 |
| `oci dns steering-policy-attachment delete` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 2 |
| `oci dns steering-policy delete` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 2 |
| `oci health-checks http-monitor delete` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 2 |
| `oci compute instance terminate` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 3 |
| `oci bv volume-group delete` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 3 |
| `oci lb load-balancer delete` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 3 |
| `oci bv volume-group update` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 4 — clearing --volume-group-replicas deletes the Phoenix replica |
| `oci db database delete` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 5 — removes the Phoenix standby from the Data Guard configuration |
| `oci db cloud-vm-cluster delete` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 7 |
| `oci db cloud-exa-infra delete` | ONE_WAY | `decommission-dr.sh` | RB-05 §5 step 7 |

Operations the runbooks direct an operator to type by hand, and that no script
issues, are deliberately **absent**: `db database switch-over-data-guard` (RB-01
§3), `db database reinstate-data-guard` (RB-03 §3), `db database
convert-standby-database-type` (RB-04 §2), `db database create-standby-database`
(RB-05 §2). Granting capability that nothing exercises is capability nobody has
tested. If one of them is ever promoted into a script, add it to the allowlist
with its citation and add a dry-run assertion in `test-scripts.sh`.

`windows/Stop-EBSAppTier.ps1` calls `oci lb backend update` from PowerShell and is
outside the guard's reach. That is a gap, recorded here rather than papered over.

---

## 2. Flags

| Flag | Meaning | Where it is required |
|---|---|---|
| `--help`, `-h` | Print usage and exit 0. | Every script. |
| `--dry-run` | Print every OCI call without issuing one. Needs no credentials and reaches no tenancy. | Every script that mutates, and every read-only script that walks the environment. |
| `--confirm` | Acknowledge a one-way door. | The three storage-failover scripts. `decommission-dr.sh` spells it `--confirm-unprotected`. |
| `--ticket` | Change reference, written into the evidence record. | Every one-way door. |
| `--approver` | Name of the signing approver. | `decommission-dr.sh` only, which also needs written sign-off from the business owner and the risk function. |
| `--reason` | Free text, written into the evidence record. | `set-dr-posture.sh` for `hot` and `drill`; `scale-exadata-ocpu.sh` when scaling down; `steer-traffic.sh` with `--force-unhealthy`. |

**Run `--dry-run` first.** It is the cheapest way to find out that an OCID in the
resource config is stale, and the one step of a failover that costs nothing.

### Per script

| Script | Mutates | `--help` | `--dry-run` | Confirmation gate |
|---|---|---|---|---|
| `oci/check-replication-health.sh` | no | yes | — reads only, no walk to preview | — |
| `oci/capture-replication-state.sh` | no | yes | yes | — |
| `oci/detect-drift.sh` | no | yes | yes | — |
| `oci/generate-rpo-attestation.sh` | no | yes | yes | — |
| `oci/set-dr-posture.sh` | reversible | yes | yes | `--reason` for `hot` / `drill` |
| `oci/scale-exadata-ocpu.sh` | reversible | yes | yes | `--reason` when scaling down |
| `oci/steer-traffic.sh` | reversible | yes | yes | `--reason` with `--force-unhealthy` |
| `oci/activate-volume-group.sh` | **one-way** | yes | yes | `--confirm` + `--ticket` |
| `oci/fss-failover.sh` | **one-way** | yes | yes | `--confirm` + `--ticket` |
| `oci/objectstore-failover.sh` | **one-way** | yes | yes | `--confirm` + `--ticket` |
| `oci/decommission-dr.sh` | **one-way** | yes | yes | `--confirm-unprotected` + `--approver` + `--ticket` |
| `dataguard/capture-lag-snapshot.sh` | no | yes | yes | — |
| `dataguard/dg-health.sh` | no | — takes no arguments | — | — |

---

## 3. Exit codes

| Code | Meaning |
|---|---|
| **0** | The work completed, or `--dry-run` / `--help` printed and stopped. |
| **1** | Runtime or environment error: the resource config is missing, a cluster is not `AVAILABLE`, a metric entry is malformed. |
| **2** | Usage error: an unknown flag, a missing required argument, two mutually exclusive arguments. |
| **3** | **Refused by a guard rail.** Nothing was done. The script is telling you the action is wrong, not that it failed. |

Exit 3 is the one that matters. It never means "try again": it means a one-way
door was opened without confirmation or a change reference, an OCPU target would
have stopped redo apply, traffic would have been steered at a dead region, an
operation was absent from the write guard's allowlist, or a read-only script was
found to contain a mutating verb. Do not work around a 3. Read what it says.

**Two documented exceptions**, both of which report findings through the exit code
because they are meant to be run from cron:

- `oci/check-replication-health.sh` — 0 green, **1 warnings**, **2 critical**, 3 configuration or tooling error (including an unknown argument).
- `oci/detect-drift.sh` — 0 no drift, **1 drift found** and the report written, 3 configuration or tooling error.

---

## 4. Testing

`./test-scripts.sh` runs offline, needs no credentials, and reaches no tenancy. It
covers the guard's unit tests, a static tripwire that fails if any script invokes
the OCI CLI mutatingly outside the guard, a dry-run walk of every mutating script
that asserts nothing outside the allowlist is emitted and nothing executes, and a
check that every `scripts/` invocation written in a runbook still names flags the
script accepts.

`shellcheck` is used when it is installed and skipped with a warning when it is
not, so the suite runs on a workstation that has not been set up for it.
