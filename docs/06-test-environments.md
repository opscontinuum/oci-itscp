# 06 — Test Environments: what each one proves, and what none of them can

The plan's runbooks make claims that a document cannot prove: that a Broker switchover to
Phoenix executes in the order written, that asynchronous redo over a 60 ms path keeps up while
synchronous redo does not, that the guard rails in `scripts/` refuse what the design says they
refuse. Three test tiers exist to turn those claims into evidence at three price points. This
document states, for each tier, what a green result proves and what it must not be read to
prove. **A green test suite must not be allowed to imply more than it demonstrates.**

| Tier | Substrate | Cost | Proves | Cannot prove |
|---|---|---|---|---|
| **A** — mocked unit tests | GitHub Actions, bats, Pester, `terraform test` with mock providers | $0 | Script guard rails, argument construction, drill-isolation abort logic, Terraform plan logic | Anything about Oracle, OCI or EBS behavior |
| **B** — Data Guard rig | Containers on Rancher Desktop, or VMs on a Harvester cluster, with injected WAN latency | $0 cloud; local hardware and Oracle developer licenses | Data Guard protection-mode behavior under latency, Broker runbook sequences, snapshot-standby drill cycle, transport-tuning maths, and (Harvester variant) an EBS application tier on Windows | Exadata behavior, OCI service mechanics, Work Recovery Time |
| **C** — cheap OCI environment | Terraform, Base Database Service instead of Exadata, apply-locked | Real spend when unlocked | Full Stack DR plans parse, precheck and execute; OCI replication mechanics; the scripts against real APIs | Exadata behavior, real EBS, Work Recovery Time, failback baseline durations |

---

## 1. Tier A — mocked unit tests ($0, runs in CI)

**What runs.** `scripts/test-scripts.sh` — five checks over the shell tier: `shellcheck` when
it is installed, the write guard's own unit tests, a static tripwire that fails if any script
calls the OCI CLI outside the guard, a dry-run walk of every mutating script asserting that
nothing outside the guard's allowlist is emitted and that nothing executes, and a check that
every `scripts/` invocation written in a runbook names flags the script accepts. A poisoned
`oci` on `PATH` records any execution, so "no tenancy was reached" is asserted rather than
assumed. `terraform validate` and `terraform test` with `mock_provider "oci"` blocks cover the
Terraform. Still to come: Pester for `scripts/windows/*.ps1` under PowerShell 7 on Linux, and
per-script assertions against a fake `oci` returning canned JSON for the branches a dry run
does not reach. GitHub Actions on push and pull request; the repository is public, so the
minutes are free.

**What a green run proves.**

- Every guard rail rejects what the design says it rejects, with exit 3: OCPU below Oracle's
  per-VM minimum or not a multiple of it; any storage one-way door without `--confirm` or a
  `--ticket`; any OCI operation absent from the write guard's allowlist (`scripts/lib/write-guard.sh`);
  decommission without `--confirm-unprotected`, an approver and a ticket, or without long-term
  backup evidence; traffic steering at a load balancer whose backend set is unhealthy.
- `Start-EBSAppTier.ps1 -DrillMode` **aborts** when any of the five scripted isolation controls
  fails or when no named person has attested the manual checks. A drill that transmits a real
  payment file is a worse outcome than no drill.
- Every documented command line in the runbooks parses against the script it invokes (a test
  greps the runbooks for `scripts/` invocations and runs each with `--help` or `--dry-run`); this
  is the check that would have caught the mismatches the adversarial review found.
- The Terraform apply lock holds: with `unlock_apply = false` every billable resource has
  `count = 0`.

**What it cannot prove.** Nothing about Oracle Database, OCI services or EBS. A fake `oci` that
returns `AVAILABLE` proves the script's logic, not the API's.

---

## 2. Tier B — the Data Guard rig ($0 cloud)

### 2.1 What it exists to prove

1. **The plan's central latency argument.** Under Maximum Availability the primary "will wait a
   maximum of NET_TIMEOUT seconds for an acknowledgment from any of the standby databases" [1],
   and under Maximum Performance redo is shipped "asynchronously with respect to transaction
   commitment, so primary database performance is unaffected" [2]. With the Phoenix member's
   network delayed to the measured inter-region latency (Oracle states Ashburn–Phoenix "exceeds
   50 ms RTT" [3]), the rig measures commit latency and transport lag with the Phoenix member
   SYNC and then ASYNC, sweeping the injected delay. The result is a graph, not an assertion.
2. **The Broker sequences in RB-01 to RB-04 execute as written**, including the steps the
   adversarial review added: protection-mode downgrade and `DISABLE FAST_START FAILOVER` before
   a switchover, `DISABLE FAST_START FAILOVER FORCE` before a failover, `REINSTATE` with
   Flashback, snapshot-standby conversion and return with queued redo applied [4].
3. **The transport-tuning maths** in `scripts/dataguard/tnsnames-tuning.md`: socket buffers at
   three times the bandwidth-delay product [1] versus defaults, at the injected latency.
4. **NET_TIMEOUT behavior**: what a synchronous standby outage does to commits for the
   configured timeout, and that the configuration reports unsynchronized afterwards [1][5].

### 2.2 Substrate options

| Option | Fits | Members | Latency injection | Notes |
|---|---|---|---|---|
| **B1 — containers** on Rancher Desktop (`docker compose`) | A workstation with 62 GB RAM | Three Oracle Database 19c Enterprise Edition containers (primary, SYNC standby standing in for Ashburn AD-2, ASYNC standby standing in for Phoenix) on one user-defined bridge network | `tc qdisc add dev eth0 root netem delay 65ms 5ms` inside the Phoenix container, which needs the `NET_ADMIN` capability; the delay is a swept variable | Database only. No application tier. |
| **B2 — VMs** on a Harvester cluster (KubeVirt) | A lab cluster with 96 GB or more | The same three database VMs, plus a Linux EBS 12.2 application tier from Oracle's Vision demo appliance, plus Windows application-tier VMs built with Ansible over WinRM to exercise the PowerShell scripts | `netem` on the virtual network between the "Ashburn" and "Phoenix" VM networks, or on the Phoenix VMs' interfaces | The only option that runs EBS. |

**Image and license points that need the user, not the rig.** Oracle's 19c Enterprise Edition
container image and the EBS Vision appliance both require an Oracle account, acceptance of
license terms, and an authenticated pull or download; the plan's automation never handles those
credentials. Oracle Database Express Edition is not a substitute: it is not listed with the
Data Guard features in the licensing table used by this plan [6], and a rig that cannot run
Data Guard proves nothing this tier exists to prove. Enterprise Edition and the EBS appliance
under developer license terms are a position the user confirms, not one this plan asserts.

**Sizing (planning estimate, not verified against Oracle's published minimums in this
revision).** Three 19c database VMs at about 8 GB each, one Linux EBS application-tier VM at
12 to 16 GB, one Phoenix application-tier VM the same, plus hypervisor and rig overhead: about
60 to 70 GB in use. A 48 GB host runs the database rig plus one application tier at a time;
96 GB runs the full topology and leaves room for a snapshot-standby drill copy.

### 2.3 What Tier B cannot prove

- **Exadata.** Smart scan, Hybrid Columnar Compression, storage-cell failure modes, and the
  online OCPU-scaling characteristics that the WARM posture depends on. The rig's "apply keeps
  up at the floor" measurement is on commodity CPU and says nothing about a 2-OCPU Exadata VM.
- **OCI services.** Volume group replication and activation, File Storage replication and its
  full base copy, Object Storage replication policies, Full Stack DR plans, Run Command,
  Traffic Management. None of these exist in the rig; Tier C is where they are tested.
- **Real EBS behavior (B1), and most of it in B2.** `adop` cycles, `FND_NODES` and
  AutoConfig, the concurrent-manager recovery path, Workflow, XML Gateway, Payments, and the
  isolation controls that keep a drill from transmitting. B2 exercises the start/stop scripts
  and the logical-host-name pattern against a Vision instance; it does not reproduce a
  production configuration.
- **Work Recovery Time.** The reconciliation and Finance sign-off that dominate MTD are
  produced only by an exercise with the functional team on real data (RB-04 §2). No rig
  measures WRT.
- **Failback baseline durations.** Full re-baseline of storage tiers is an OCI phenomenon.

---

## 3. Tier C — cheap OCI, no Exadata (author only, never apply)

**Posture.** The Terraform under `terraform/` is complete, apply-locked behind
`unlock_apply` and a spend acknowledgement that names a delta and a duration, BYOL by default,
with a single documented teardown command. It has never been applied. `terraform validate` and
`terraform test` with mock providers run offline; a real `terraform plan` requires the
operator's own OCI session authentication.

**What an 8-hour BYOL smoke campaign would prove**, if a spend override is ever given: that the
Full Stack DR protection groups accept every member type the plan uses, that all four plans
generate and their prechecks pass, that the Object Storage built-in plan groups do what the
plan says, that the scripts' OCI calls are correct against real APIs, and that Base Database
Service Active Data Guard needs Enterprise Edition Extreme Performance [6][7]. Data Guard
between two Base Database systems stands in for Exadata.

**What Tier C cannot prove.** Exadata behavior (it is deliberately absent); real EBS (no EBS
runs on the cheap environment); Work Recovery Time; and failback baseline durations at production
data volumes, because the smoke environment holds a few hundred gigabytes.

---

## 4. Reading a green result

| Result | Say | Do not say |
|---|---|---|
| Tier A green | The scripts and Terraform behave as designed | The design works |
| Tier B green | The Data Guard design behaves as designed at the injected latency; the Broker runbook steps are in the right order | The RTO or RPO targets are met; the WARM floor keeps up on Exadata |
| Tier C green | The OCI orchestration and replication mechanics work on a small environment | The production environment will fail over in 60 minutes |
| A Level 2 drill with Finance (RB-04) | The measured RTO and WRT are these numbers | — |

Only the last row produces the numbers that `docs/02-mtd-tiers.md` is allowed to publish.

---

## References

This document is a synthesis: every statement about product behavior or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *High Availability Overview and Best Practices.* Oracle Database 19c (F23691-56, July 14
   2026), accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/haovw/high-availability-overview-and-best-practices.pdf>
   — Supports: Maximum Availability waits up to NET_TIMEOUT for an acknowledgement; socket
   buffers at 3× the bandwidth-delay product (§2.1).
2. *Oracle Data Guard Protection Modes.* Oracle Data Guard Concepts and Administration 19c,
   accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-protection-modes.html>
   — Supports: Maximum Performance ships redo asynchronously with respect to commit (§2.1).
3. *Set Up FMW Stretched Clusters.* Oracle Solutions (G49655-02, March 2026), accessed
   2026-09-01. <https://docs.oracle.com/en/solutions/fmw-stretched-clusters/set-fmw-stretched-clusters1.html>
   — Supports: Ashburn–Phoenix latency "exceeds 50 ms RTT" (§2.1).
4. *Managing Physical and Snapshot Standby Databases.* Oracle Data Guard Concepts and
   Administration 19c, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/managing-oracle-data-guard-physical-standby-databases.html>
   — Supports: snapshot standby receives but does not apply redo; queued redo applied on
   conversion back (§2.1).
5. *Switchover and Failover Operations.* Oracle Data Guard Broker 19c, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html>
   — Supports: fast-start failover cannot occur when the target standby was not synchronized;
   switchover and manual failover only to the fast-start failover target while it is enabled
   (§2.1).
6. *Database Licensing Information User Manual 19c.* Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html>
   — Supports: the Data Guard feature availability table by edition (§2.2, §3).
7. *About Oracle Data Guard (Base Database Service).* Oracle Cloud Infrastructure
   Documentation, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/base-database/doc/use-oracle-data-guard-db-system.html>
   — Supports: "Active Data Guard requires Enterprise Edition Extreme Performance" (§3).

### Unverified statements

- The `tc netem` and KubeVirt/Harvester mechanics, and the RAM sizing in §2.2, are engineering
  judgment; no vendor documentation for them was read in this revision.
- That Oracle Database Express Edition lacks Data Guard is inferred from its absence in the
  licensing table's Data Guard rows, not from an explicit statement.

[1]: https://docs.oracle.com/en/database/oracle/oracle-database/19/haovw/high-availability-overview-and-best-practices.pdf "HA Overview and Best Practices 19c"
[2]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-protection-modes.html "Data Guard Protection Modes 19c"
[3]: https://docs.oracle.com/en/solutions/fmw-stretched-clusters/set-fmw-stretched-clusters1.html "Set Up FMW Stretched Clusters"
[4]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/managing-oracle-data-guard-physical-standby-databases.html "Managing Physical and Snapshot Standby Databases 19c"
[5]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html "Switchover and Failover Operations — Broker 19c"
[6]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html "Database Licensing Information 19c"
[7]: https://docs.oracle.com/en-us/iaas/base-database/doc/use-oracle-data-guard-db-system.html "About Oracle Data Guard — Base Database Service"
