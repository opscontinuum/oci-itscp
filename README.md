# oci-itscp — IT Service Continuity Plan

**Oracle E-Business Suite on Exadata · OCI · `us-ashburn-1` → `us-phoenix-1`**

A complete, executable DR solution: architecture, tiered MTD targets, replication design,
runbooks, and the automation that switches the estate between postures.

---

## Start here

| If you are… | Read |
|---|---|
| An executive or business owner | [`docs/02-mtd-tiers.md`](docs/02-mtd-tiers.md) — the tiers and what they cost |
| An architect | [`docs/01-architecture.md`](docs/01-architecture.md) → [`docs/03-replication-matrix.md`](docs/03-replication-matrix.md) |
| On call, right now | [`runbooks/RB-02-failover.md`](runbooks/RB-02-failover.md) — start at §0, the decision gate |
| Building this | [`runbooks/RB-05-replication-lifecycle.md`](runbooks/RB-05-replication-lifecycle.md) §2 |
| Running a DR test | [`runbooks/RB-04-dr-drill.md`](runbooks/RB-04-dr-drill.md) |
| Asked to cut DR cost | [`docs/05-cost-and-teardown.md`](docs/05-cost-and-teardown.md) |

---

## Design in one paragraph

Three **Oracle Data Guard** members: primary in Ashburn AD-1, a **SYNC** standby in Ashburn
AD-2 giving RPO 0 with automatic Fast-Start Failover for the likely failure (an AD or rack
event), and an **Active Data Guard ASYNC** standby in Phoenix for regional disaster.
Cross-region SYNC is not viable at ~60–70 ms RTT, so the two jobs are split rather than
compromised. Windows application, concurrent-processing, and visualization tiers are
pre-provisioned in Phoenix with **identical hostnames** resolved by split-horizon private
DNS — the single largest RTO lever in the plan, worth roughly 3–5 hours. Storage replicates
natively per tier: **Volume Group Replication** for block, **FSS File System Replication**
for shared filesystems, **Object Storage Replication Policy** for batch interchange, and
**Autonomous Recovery Service** with cross-region backup copy as the independent,
ransomware-resistant failure domain. **OCI Full Stack Disaster Recovery** orchestrates
switchover, failover, and non-disruptive drills.

## MTD tiers

| Tier | RPO | RTO | WRT | **MTD** | Scope |
|---|---|---|---|---|---|
| **0 Platinum** | 0 → <30 s | ≤ 60 min | ~30 min | **≤ 2 hr** | Core financials, OM, the database |
| **1 Gold** | ≤ 5 min | ≤ 4 hr | ~2 hr | **≤ 6 hr** | Full app tier, CM, Workflow, integrations |
| **2 Silver** | ≤ 1 hr | ≤ 12 hr | ~4 hr | **≤ 24 hr** | BI / visualization, non-critical interfaces |
| **3 Bronze** | ≤ 24 hr | ≤ 72 hr | ~8 hr | **≤ 5 days** | Non-production, archive |

**MTD = RTO + WRT.** Work Recovery Time — reconciliation, interface replay, Finance
sign-off — is tracked separately because for an ERP it is often larger than RTO, and no
infrastructure spend shrinks it. Details in [`docs/02-mtd-tiers.md`](docs/02-mtd-tiers.md).

> The MTD figures above are **design targets** until a Level 2 drill measures them. See
> [`runbooks/RB-04-dr-drill.md`](runbooks/RB-04-dr-drill.md) §5.

## Postures — spin-up and tear-down

```bash
./scripts/oci/set-dr-posture.sh --posture warm     # steady state, ~45-60% of prod cost
./scripts/oci/set-dr-posture.sh --posture hot      # Tier 0 readiness, elevate in minutes
./scripts/oci/set-dr-posture.sh --posture drill    # non-disruptive test (RB-04)
```

**The governing rule: tear down compute, never tear down replication.** Replica storage is
roughly 11% of the DR bill; compute is roughly 46%. Deleting Volume Group Replication, FSS
File System Replication, or an Object Storage Replication Policy forces a **full baseline
copy** on re-enable — trading the cheapest line item for a multi-hour unprotected window.
The tooling refuses to do it. Rationale in
[`docs/03-replication-matrix.md`](docs/03-replication-matrix.md) §3.

## Repository layout

```
docs/         Architecture, MTD tiers, replication matrix, monitoring, cost
  diagrams/   SVG source for the timeline and tier ladder
runbooks/     RB-01 switchover · RB-02 failover · RB-03 failback
              RB-04 drill · RB-05 replication lifecycle
scripts/
  oci/        Posture control, health checks, guarded storage-failover actions
  dataguard/  Broker health, HCC check, redo transport tuning
  windows/    EBS app tier start/stop, drill isolation enforcement
  ebs/        EBS SQL helpers (see note below)
terraform/    Resource inventory template and module scaffolding
checklists/   Prechecks, drill timing, authority matrix, workshop, cost model
evidence/     Drill results, attestations, posture log (gitignored except structure)
```

## Setup

```bash
cp terraform/dr-resources.env.example terraform/dr-resources.env
# populate OCIDs from Terraform outputs, then:
./scripts/oci/check-replication-health.sh
```

## Before you build — confirm these

The design rests on stated assumptions in
[`docs/01-architecture.md`](docs/01-architecture.md) §1. Four are **material** — if any is
wrong, part of the design changes:

1. **EBS 12.2.x** (dual filesystem, WebLogic) rather than 12.1
2. **ExaDB-D** rather than Exadata Cloud@Customer
3. **"Visualization tier" = BI / reporting**, not *virtualization* (Hyper-V / VMware / OCVS)
4. **No Hybrid Columnar Compression** — run [`scripts/dataguard/check-hcc.sql`](scripts/dataguard/check-hcc.sql); if it returns rows, a non-Exadata standby is off the table

## Not vendored here

`scripts/ebs/cmclean.sql` is Oracle-supplied (My Oracle Support Doc ID 134007.1) and is not
redistributable. Download the current version and place it there — `Start-EBSAppTier.ps1`
fails loudly if it is missing rather than starting Concurrent Managers without it.

EBS DR cloning follows My Oracle Support Doc ID 1963472.1, *Business Continuity for Oracle
E-Business Suite Release 12.2 using a Physical Standby Database*.

## Status

Design complete and reviewed. **Not yet validated by a Level 2 drill** — the build is not
finished until one passes (RB-05 §2 Phase 6).
