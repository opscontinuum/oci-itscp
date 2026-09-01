# oci-itscp — IT Service Continuity Plan (worked example)

**Oracle E-Business Suite on Exadata · OCI · `us-ashburn-1` → `us-phoenix-1`**

> ### ⚠️ This is an example repository
>
> It documents a **hypothetical corporation's** DR plan. There is no real infrastructure
> behind it, no real OCIDs, no real hostnames, and no live estate. Every identifier is a
> placeholder.
>
> It exists to be a **complete, honest reference implementation** — architecture, tiered
> MTD targets, replication design, runbooks, and working automation — that you can read
> end to end and then adapt. It is not a template to point at production unmodified.
>
> If you are building a real plan, see [How to use this repo](#how-to-use-this-repo) below.
> The short version: **fork it private.**

---

## The scenario

A mid-to-large enterprise running Oracle E-Business Suite on Exadata in OCI, protecting it
across availability domains and regions:

| | Location | Role |
|---|---|---|
| **Production** | `us-ashburn-1` **AD-1** | Primary EBS database + Windows application, concurrent-processing, and visualization tiers |
| **Local HA** | `us-ashburn-1` **AD-2** | Synchronous Oracle Data Guard standby — RPO 0, automatic Fast-Start Failover |
| **Regional DR** | `us-phoenix-1` | Active Data Guard ASYNC standby + pilot-light Windows tiers |

Two availability domains in Ashburn, one region away in Phoenix. That split is deliberate
and is the central design argument of the plan (see below) — it separates the *likely*
failure from the *catastrophic* one instead of compromising on a single mechanism for both.

The worked example will continue to be built out: Terraform modules, Full Stack DR plan
definitions, and sample evidence artifacts.

---

## How to use this repo

### If you are evaluating an approach
Read it straight through in this order. It is written to be read, not just referenced:

1. [`docs/01-architecture.md`](docs/01-architecture.md) — the design and *why* each choice was made
2. [`docs/02-mtd-tiers.md`](docs/02-mtd-tiers.md) — how downtime tiers are derived and costed
3. [`docs/03-replication-matrix.md`](docs/03-replication-matrix.md) — every mechanism, and which ones are one-way doors
4. [`runbooks/`](runbooks/) — what actually happens during a switchover, failover, failback, and drill

### If you are building a real plan from this

**1. Fork it private.** Your populated version accumulates genuine operational detail —
OCIDs, hostnames, lag figures, incident narratives, drill results. None of that belongs in
a public repository.

```bash
gh repo create <your-org>/itscp --private --clone
# copy the contents of this repo in as your starting point
```

**2. Work the assumptions first.** [`docs/01-architecture.md`](docs/01-architecture.md) §1
lists seven stated assumptions; four are marked **[MATERIAL]** and change the design if
wrong. Resolve those before building anything.

**3. Run the tier workshop before the build, not after.**
[`checklists/tier-assignment-workshop.md`](checklists/tier-assignment-workshop.md) is a
half-day agenda that gets the business to own the MTD targets. Doing this late means
rebuilding to numbers you could have known up front.

**4. Populate the resource inventory.**

```bash
cp terraform/dr-resources.env.example terraform/dr-resources.env
# fill in real OCIDs — this file is gitignored and must stay that way
./scripts/oci/check-replication-health.sh
```

**5. Replace the design targets with measurements.** Every MTD figure in this repo is a
*design target*. They become commitments only after a Level 2 drill measures them
([`runbooks/RB-04-dr-drill.md`](runbooks/RB-04-dr-drill.md) §5).

### If you are on call right now
[`runbooks/RB-02-failover.md`](runbooks/RB-02-failover.md) — start at §0, the decision gate.

---

## A note on `evidence/`

In **this** repository, `evidence/` is a structural placeholder. Anything added here will be
clearly-labelled illustrative sample data for the hypothetical corporation.

In **your** copy it becomes the most sensitive directory in the repo. It holds drill timing
sheets, RPO attestations, the posture log, in-flight concurrent request captures, and
post-incident findings — real hostnames, real lag figures, real narratives about how your
recovery went. It is also the directory an auditor will ask for.

`.gitignore` currently excludes `evidence/*.csv` and `evidence/*.json`. **Markdown under
`evidence/` is not ignored**, and the drill and precheck templates produce Markdown. Before
you commit any real drill output, either:

- tighten the pattern to `evidence/*` (keeping `!evidence/.gitkeep`), or
- keep evidence in a separate private repository and reference it from here

Decide this before the first drill, not after.

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
evidence/     Drill results, attestations, posture log — read the note above
```

## Not vendored here

`scripts/ebs/cmclean.sql` is Oracle-supplied (My Oracle Support Doc ID 134007.1) and is not
redistributable. Download the current version and place it there — `Start-EBSAppTier.ps1`
fails loudly if it is missing rather than starting Concurrent Managers without it.

EBS DR cloning follows My Oracle Support Doc ID 1963472.1, *Business Continuity for Oracle
E-Business Suite Release 12.2 using a Physical Standby Database*.

## Status

Design complete and internally consistent. Not validated against a live estate — by
construction, since the scenario is hypothetical.

Planned build-out:

- [ ] Terraform modules for the Phoenix estate and both Ashburn ADs
- [ ] OCI Full Stack Disaster Recovery plan definitions and user-defined steps
- [ ] OCI Monitoring alarm definitions as code (`docs/04-monitoring.md` §2)
- [ ] Illustrative sample evidence — a worked drill timing sheet and RPO attestation

## Scope and limitations

- Product behaviour reflects OCI and Oracle Database documentation as understood at
  authoring time. **Verify current service limits, replication intervals, and feature
  availability against Oracle documentation for your tenancy** before relying on any
  specific figure — several are explicitly flagged in-line as needing confirmation.
- Cost percentages describe the *shape* of a typical bill. They are not a quote and exclude
  licensing, which is the line item most often discovered late
  ([`docs/05-cost-and-teardown.md`](docs/05-cost-and-teardown.md) §4).
- Latency figures (~60–70 ms IAD↔PHX) are representative. Measure your own; every RPO claim
  in the plan derives from that number.
