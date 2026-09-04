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
| **Production** | `us-ashburn-1` **AD-1 and AD-2** | Primary EBS database in AD-1; Windows application, concurrent-processing, and visualization tiers split across both ADs behind one load balancer |
| **Local HA** | `us-ashburn-1` **AD-2** | Synchronous Oracle Data Guard standby — RPO 0 while synchronized [1], automatic Fast-Start Failover [2]; the AD-2 application nodes keep the service reachable |
| **Regional DR** | `us-phoenix-1` | Active Data Guard ASYNC standby [1] [3] + pilot-light Windows tiers |

Two availability domains in Ashburn, one region away in Phoenix. That split is deliberate
and is the central design argument of the plan (see below) — it separates the *likely*
failure from the *catastrophic* one instead of compromising on a single mechanism for both.

The worked example now includes apply-locked Terraform (never applied) and Full Stack DR plan
definitions; sample evidence artifacts and the test tiers in `docs/06` are still to come.

---

## How to use this repo

This plan is a synthesis, not original work: every statement about product behaviour or a
standard carries a marker such as [1] linking to the source it was derived from, and any
statement that could not be traced to a source is marked as unverified engineering
judgement. The consolidated index is `docs/references.md`; the per-citation audit is
`docs/citation-audit.md`. The ITIL 4, NIST and DoD alignment is in `docs/07-itil4-alignment.md`.

### If you are evaluating an approach
Read it straight through in this order. It is written to be read, not just referenced:

0. [`docs/00-record-of-changes.md`](docs/00-record-of-changes.md) — what has changed in the plan, when, and who signed it off
1. [`docs/01-architecture.md`](docs/01-architecture.md) — the design and *why* each choice was made
2. [`docs/02-mtd-tiers.md`](docs/02-mtd-tiers.md) — how downtime tiers are derived and costed
3. [`docs/03-replication-matrix.md`](docs/03-replication-matrix.md) — every mechanism, and which ones are one-way doors
4. [`runbooks/`](runbooks/) — what actually happens during a switchover, failover, failback, and drill
5. [`docs/06-test-environments.md`](docs/06-test-environments.md) — what each test tier proves, and what none of them can
6. [`docs/07-itil4-alignment.md`](docs/07-itil4-alignment.md) — how the vocabulary maps to ITIL 4, ISO 22301, NIST and DoD instruments
7. [`checklists/contact-roster.md`](checklists/contact-roster.md) — who is notified, in what order, and how they are reached; the contact-list appendix NIST SP 800-34 expects
8. [`docs/00-plan-approval.md`](docs/00-plan-approval.md) — the approval statement that makes it a plan rather than a design; unsigned here by design. It closes the plan because it affirms that everything above it is complete
9. [`checklists/contingency-training.md`](checklists/contingency-training.md) — the training programme NIST SP 800-34 keeps separate from drills: annual syllabus, new-joiner path, closed-book evidence. It runs against the approved plan, so it follows the signature

### If you are building a real plan from this

**1. Fork it private.** Your populated version accumulates genuine operational detail —
OCIDs, hostnames, lag figures, incident narratives, drill results. None of that belongs in
a public repository.

```bash
gh repo create <your-org>/itscp --private --clone
# copy the contents of this repo in as your starting point
```

**2. Work the assumptions first.** [`docs/01-architecture.md`](docs/01-architecture.md) §1
lists seven stated assumptions; three are marked **[MATERIAL]** and change the design if
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
AD-2 giving RPO 0 [1] with automatic Fast-Start Failover [2] for the likely failure (an AD or
rack event), and an **Active Data Guard ASYNC** standby in Phoenix for regional disaster [1] [3].
Cross-region SYNC is not viable because a synchronous commit waits for the standby
acknowledgement [1] and Oracle states that Ashburn–Phoenix latency exceeds 50 ms RTT [4]
(the ~60–70 ms used in this plan is a representative figure; measure your own). So the two
jobs are split rather than compromised. Windows application, concurrent-processing, and
visualization tiers are pre-provisioned in Phoenix under their own physical names, with EBS
configured on **logical host names** that are the same in both regions and resolved
region-locally — the pattern Oracle documents for EBS business continuity [5] [6] — the
single largest RTO lever in the plan, worth roughly
3–5 hours *(unverified: engineering judgement; no documentation found in this revision)*.
Storage replicates natively per tier: **Volume Group Replication** for block [7], **FSS File
System Replication** for shared filesystems [8], **Object Storage Replication Policy** for
batch interchange [9], and **Autonomous Recovery Service** protecting the primary as the
immutable, ransomware-resistant copy [10] [11] [15] [13]. OCI automatic backups cannot be
enabled on the standby while the primary uses Recovery Service [14] (the general standby-backup
capability [12] is conditioned on an Object Storage primary destination), so the Phoenix copy while
Ashburn is primary is a customer-scheduled RMAN backup of the standby to Object Storage
*(unverified: engineering judgement)*; after any role change Recovery Service is enabled on the
new primary [14]. **OCI Full Stack Disaster
Recovery** orchestrates switchover, failover, and non-disruptive drills [16].

## MTD tiers

| Tier | RPO | RTO | WRT | **MTD** | Scope |
|---|---|---|---|---|---|
| **0 Platinum** | 0 → <30 s | ≤ 60 min | ~30 min | **≤ 2 hr** | Core financials, OM, the database |
| **1 Gold** | ≤ 5 min | ≤ 4 hr | ~2 hr | **≤ 6 hr** | Full app tier, CM, Workflow, integrations |
| **2 Silver** | ≤ 1 hr | ≤ 12 hr | ~4 hr | **≤ 24 hr** | BI / visualization, non-critical interfaces |
| **3 Bronze** | ≤ 24 hr | ≤ 72 hr | ~8 hr | **≤ 5 days** | Non-production, archive |

The figures are this plan's own design targets for the hypothetical corporation; they are
not derived from any source. The vocabulary is NIST SP 800-34 Rev. 1 [17]: MTD is "the total
amount of time the system owner/authorizing official is willing to accept for a
mission/business process outage or disruption", and the RTO "must normally be shorter than
the MTD" because "additional processing time must be added to the RTO to stay within the
time limit established by the MTD" [17]. **MTD = RTO + WRT** is this plan's decomposition of
that statement: Work Recovery Time — reconciliation, interface replay, Finance sign-off — is
the plan's name for NIST's additional processing time. NIST does not use the term WRT, and
states that RPO "is not considered as part of MTD" [17]. WRT is tracked separately because for
an ERP it is often larger than RTO, and no infrastructure spend shrinks it *(unverified:
engineering judgement; no documentation found in this revision)*. Details in
[`docs/02-mtd-tiers.md`](docs/02-mtd-tiers.md).

## Postures — spin-up and tear-down

```bash
./scripts/oci/set-dr-posture.sh --posture warm     # steady state, ~45-60% of prod cost
./scripts/oci/set-dr-posture.sh --posture hot --reason "<threat, ticket>"   # Tier 0 readiness, elevate in minutes
./scripts/oci/set-dr-posture.sh --posture drill --reason "RB-04 <date>"    # non-disruptive test (RB-04)
```

**The governing rule: tear down compute, never tear down replication.** Replica storage is
roughly 11% of the DR bill; compute is roughly 46% *(unverified: engineering judgement; no
documentation found in this revision — illustrative cost shape, see `docs/05-cost-and-teardown.md`)*.
Deleting a replication mechanism to save that line item is a one-way door: disabling Volume
Group Replication deletes the replica, and re-enabling "starts the replication process from
scratch" with an initial sync that "can take hours" (stated by Oracle in the volume-resize
context) [7]; an FSS replication target that has been exported cannot be reused and
re-establishing replication needs a full base copy [18]; and a new Object Storage
Replication Policy does not replicate objects that already exist in the source bucket, so a
bulk copy must precede it [9]. The cheapest line item is traded for a multi-hour unprotected
window. The tooling refuses to do it. Rationale in
[`docs/03-replication-matrix.md`](docs/03-replication-matrix.md) §3.

## Repository layout

```
docs/         01 architecture · 02 MTD tiers · 03 replication matrix · 04 monitoring
              05 cost · 06 test environments · 07 ITIL 4 / NIST / DoD alignment
              references index · citation audit
  diagrams/   SVG source for the timeline and tier ladder
runbooks/     RB-01 switchover · RB-02 failover · RB-03 failback
              RB-04 drill · RB-05 replication lifecycle
scripts/
  README.md   The command-line contract: flags, exit codes, the write guard allowlist
  test-scripts.sh  Offline test suite for the shell tier; reaches no tenancy
  lib/        write-guard.sh — the allowlist every mutating OCI call goes through
  oci/        Posture control, health checks, guarded storage-failover actions,
              forensic capture, OCPU scaling, traffic steering, drift detection,
              RPO attestation, guarded decommission
  dataguard/  Broker health, lag snapshot, HCC check, redo transport tuning
  windows/    EBS app tier start/stop, drill isolation enforcement, in-guest drift audit
  ebs/        EBS SQL helpers (see note below)
terraform/    Resource inventory template (modules are planned; see Status)
checklists/   Prechecks, drill timing, authority matrix, workshop, cost model
evidence/     Drill results, attestations, posture log — read the note above
```

## Not vendored here

`scripts/ebs/cmclean.sql` is Oracle-supplied (My Oracle Support Doc ID 134007.1,
*Concurrent Processing - CMCLEAN.SQL - Non Destructive Script to Clean Concurrent Manager
Tables* [19] [20]) and is not redistributable. Download the current version and place it
there — `Start-EBSAppTier.ps1` fails loudly if it is missing rather than starting Concurrent
Managers without it. **Applicability caveat:** a public source states that note 134007.1 "is
valid for Applications versions 10.7 to 12.1.3" [20], and the publicly available copy of the
12c-era EBS 12.2 business-continuity note (1963472.1) contains no cmclean step [25]; the 19c
note (2617787.1) could not be read. cmclean remains a widely
used practice, but confirm its applicability to your 12.2 patch level with Oracle Support
before relying on it.

EBS DR cloning follows the My Oracle Support business-continuity notes for Release 12.2:
Doc ID 2617787.1, *Business Continuity for Oracle E-Business Suite Release 12.2 on Oracle
Database 19c Using Physical Host Names* [21] [22] [23], and Doc ID 2246690.1, *Business
Continuity for Oracle E-Business Suite Release 12.2 using Logical Host Names* [5] [6] — the
latter being the pattern this plan uses. Doc ID 1963472.1 is the earlier Oracle Database
12c (12.1.0.2) note [24] [25], not the 19c one.

## Status

Design complete; every product-behaviour claim carries a citation and the citation audit
(`docs/citation-audit.md`) records what could and could not be verified. Not validated
against a live estate — by construction, since the scenario is hypothetical.

Planned build-out:

- [x] Terraform modules for the Phoenix estate and both Ashburn ADs — `terraform/`, **with caveat**:
      author-only, never applied against a real tenancy (no credentials on this machine, none
      committed here). Every resource is gated behind an explicit apply lock
      (`unlock_apply` + a typed `spend_acknowledgement`, see `terraform/README.md` "Apply
      lock") that defaults to zero resources. `terraform init -backend=false`,
      `terraform fmt -recursive -check`, `terraform validate`, and `terraform test`
      (`mock_provider "oci" {}`, no credentials) all pass; `plan`/`apply` were never run.
- [x] OCI Full Stack Disaster Recovery plan definitions — `terraform/modules/fsdr/`: a DR
      Protection Group peer pair plus the four plan types (Switchover, Failover, Start
      Drill, Stop Drill). User-defined steps (the PowerShell Run Command scripts
      themselves) are not yet written — see `docs/01-architecture.md` §6.
- [x] OCI Monitoring alarm definitions as code (`docs/04-monitoring.md` §2) — `terraform/modules/monitoring/`
- [ ] Illustrative sample evidence — a worked drill timing sheet and RPO attestation

## Scope and limitations

- Product behaviour reflects OCI and Oracle Database documentation as read on 2026-09-01
  (see References). **Verify current service limits, replication intervals, and feature
  availability against Oracle documentation for your tenancy** before relying on any
  specific figure — several are explicitly flagged in-line as needing confirmation.
- The MTD / RTO / RPO framing follows NIST SP 800-34 Rev. 1 [17]; how this plan derives WRT
  and MTD from it is explained in [`docs/02-mtd-tiers.md`](docs/02-mtd-tiers.md) §1.
- Cost percentages describe the *shape* of a typical bill. They are not a quote and exclude
  licensing, which is the line item most often discovered late
  ([`docs/05-cost-and-teardown.md`](docs/05-cost-and-teardown.md) §4).
- Latency figures (~60–70 ms IAD↔PHX) are representative, not an Oracle-published number;
  Oracle's published statement is only that the round trip "exceeds 50 ms" [4]. Measure your
  own; every RPO claim in the plan derives from that number.

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *Oracle Data Guard Protection Modes.* Oracle Data Guard Concepts and Administration 19c, Oracle, no version date shown, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-protection-modes.html> — Supports: Maximum Availability commits wait for standby acknowledgement (RPO 0 for the SYNC standby); Maximum Performance sends redo asynchronously (ASYNC standby); a synchronous commit waits for the standby ("Design in one paragraph", scenario table).
2. *Switchover and Failover Operations.* Oracle Data Guard Broker 19c (E96245-04), Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html> — Supports: Fast-Start Failover with an observer on a separate host (scenario table, design paragraph).
3. *Managing Physical and Snapshot Standby Databases.* Oracle Data Guard Concepts and Administration 19c, Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/managing-oracle-data-guard-physical-standby-databases.html> — Supports: Active Data Guard real-time query on an open physical standby (scenario table, design paragraph).
4. *Set Up FMW Stretched Clusters.* Oracle Solutions (G49655-02, March 2026), accessed 2026-09-01.
   <https://docs.oracle.com/en/solutions/fmw-stretched-clusters/set-fmw-stretched-clusters1.html> — Supports: "the latency between these regions [Ashburn and Phoenix] exceeds 50 ms RTT" (design paragraph, scope and limitations).
5. *Business Continuity for Oracle E-Business Suite Release 12.2 using Logical Host Names.* My Oracle Support Doc ID 2246690.1, Oracle. Unverifiable by URL: login-gated (My Oracle Support). Title corroborated only by [6], which cites it.
6. *E-Business Suite Release 12.2 Maximum Availability Architecture.* Oracle White Paper, January 2018, accessed 2026-09-01.
   <https://www.oracle.com/technetwork/database/availability/ebs-122-maa-whitepaper-4258573.pdf> — Supports: cites Doc ID 2246690.1 by title (corroborates the title only); documents the logical-host-names pattern for EBS business continuity (design paragraph, "Not vendored here").
7. *Block Volume Replication.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/volumereplication.htm> — Supports: cross-region volume and volume group replication (design paragraph); disabling replication deletes the replica and re-enabling "starts the replication process from scratch" with an initial sync that "can take hours", stated in the resize context (postures).
8. *File System Replication.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/Content/File/Tasks/FSreplication.htm> — Supports: FSS cross-region File System Replication (design paragraph).
9. *Object Storage Replication.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usingreplication.htm> — Supports: replication policy mechanism (design paragraph); "Objects uploaded to a source bucket before policy creation aren't replicated" (postures).
10. *Recovery Service Technical Architecture.* Oracle Database Autonomous Recovery Service documentation, no version shown, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/recovery-service/doc/recovery-service-architecture.html> — Supports: "Auto-backup replication is used for backup high-availability within a region. You can restore to any availability domain, zone, or region." (design paragraph).
11. *Implement Oracle Database Autonomous Recovery Service with Oracle Database@Azure.* Oracle Solutions playbook (G24007-01, January 2025), accessed 2026-09-01.
    <https://docs.oracle.com/en/solutions/implement-recovery-service-db-at-azure/index.html> — Supports: "For cross region backups, use Oracle Data Guard to replicate databases from primary to standby region and backup each region with local recovery service." (design paragraph).
12. *Manage Database Backup and Recovery on Exadata Database Service on Dedicated Infrastructure.* Oracle Cloud Infrastructure Documentation, no version shown, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/exadatacloud/doc/ecs-managing-db-backup-and-recovery.html> — Supports: "You can enable the Automatic Backup feature on a database with the standby role in a Data Guard association." (design paragraph).
13. *Using Retention Lock to Protect Backups.* Oracle Database Autonomous Recovery Service documentation, no version shown, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/recovery-service/doc/about-policy-locking.html> — Supports: retention lock prohibits modification or deletion of backups until the retention period expires (design paragraph).
14. *Backup and Restore from a Standby Database in a Data Guard Environment.* OCI release note, August 24, 2023, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/releasenotes/changes/19e890da-7b15-4d55-a0b3-28058930a8f8/> — Supports: after switchover or failover, backups are disabled on the new standby / new disabled standby (design paragraph).
15. *About Oracle Database Autonomous Recovery Service.* Oracle documentation, no version shown, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/recovery-service/doc/about-recovery-service.html> — Supports: immutability and ransomware positioning (design paragraph).
16. *Types of Disaster Recovery Plans.* OCI Full Stack Disaster Recovery documentation, © 2026, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/dr-plans-type.html> — Supports: Switchover, Failover, Start Drill and Stop Drill plan types; drills run "without interrupting the production environment" (design paragraph).
17. *Contingency Planning Guide for Federal Information Systems.* NIST Special Publication 800-34 Rev. 1, May 2010 (errata 2010-11-11), accessed 2026-09-01.
    <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf> — Supports: MTD, RTO and RPO definitions (§3.2.1, p. 17); "the RTO must normally be shorter than the MTD"; "additional processing time must be added to the RTO"; "RPO is not considered as part of MTD"; the term Work Recovery Time does not occur in the document (MTD tiers, scope and limitations).
18. *Creating a Replication.* Oracle Cloud Infrastructure File Storage documentation, © 2026, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/Content/File/Tasks/fsreplication-creating-a-replication.htm> — Supports: a previously used target can be reused only if it was never exported, which "can avoid a full base copy" (postures).
19. *Concurrent Processing - CMCLEAN.SQL - Non Destructive Script to Clean Concurrent Manager Tables.* My Oracle Support Doc ID 134007.1, Oracle. Unverifiable by URL: login-gated (My Oracle Support). Title corroborated only by [20].
20. *Be Warned: cmclean.sql Is Dangerous!* Maris Elsins, Pythian blog, 2013-07-18, accessed 2026-09-01.
    <https://www.pythian.com/blog/be-warned-cmclean-sql-is-dangerous/> — Supports: corroborates the title of Doc ID 134007.1 only; states the note "is valid for Applications versions 10.7 to 12.1.3" ("Not vendored here").
21. *Business Continuity for Oracle E-Business Suite Release 12.2 on Oracle Database 19c Using Physical Host Names.* My Oracle Support Doc ID 2617787.1, Oracle. Unverifiable by URL: login-gated (My Oracle Support). Title corroborated only by [22] and [23].
22. *Collection of EBS upgrade information for Oracle Database 19c and 26ai.* Mike Dietrich, personal blog, 2020-06-30, accessed 2026-09-01.
    <https://mikedietrichde.com/2020/06/30/collection-of-ebs-upgrade-information-for-oracle-database-19c/> — Supports: corroborates the title and ID of Doc ID 2617787.1 only.
23. *EBS on Oracle Database 19c — supported.* Erman Arslan's Oracle Blog, 2020-05-02, accessed 2026-09-01.
    <http://ermanarslan.blogspot.com/2020/05/ebs-on-oracle-database-19c-supported.html> — Supports: corroborates the title and ID of Doc ID 2617787.1 only.
24. *Business Continuity for Oracle E-Business Suite Release 12.2 Using Oracle 12c (12.1.0.2) Physical Standby Database.* My Oracle Support Doc ID 1963472.1, Oracle. Unverifiable by URL: login-gated (My Oracle Support). Title corroborated only by [25].
25. *Business Continuity for Oracle EBS R12.2* (third-party copy of Doc ID 1963472.1). pdfcoffee.com, undated, accessed 2026-09-01.
    <https://pdfcoffee.com/business-continuity-for-oracle-ebsr122-pdf-free.html> — Supports: corroborates the title and 12c scope of Doc ID 1963472.1 only; the copy contains no cmclean step, its post-transition cleanup being `fnd_net_services.remove_system`, `fnd_conc_clone.setup_clean` and `ad_zd_fixer.clear_valid_nodes_info` ("Not vendored here").

### Unverified statements

The following statements are engineering judgement with no supporting documentation found in this revision:

- Logical host names are worth roughly 3–5 hours of RTO ("Design in one paragraph").
- WRT is often larger than RTO for an ERP and no infrastructure spend shrinks it ("MTD tiers").
- Replica storage is roughly 11% and compute roughly 46% of the DR bill; the warm posture is ~45–60% of production cost ("Postures").

[1]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-protection-modes.html "Oracle Data Guard Protection Modes — Oracle"
[2]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html "Switchover and Failover Operations — Oracle Data Guard Broker 19c"
[3]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/managing-oracle-data-guard-physical-standby-databases.html "Managing Physical and Snapshot Standby Databases — Oracle"
[4]: https://docs.oracle.com/en/solutions/fmw-stretched-clusters/set-fmw-stretched-clusters1.html "Set Up FMW Stretched Clusters — Oracle"
[5]: #references "MOS Doc ID 2246690.1 — unverifiable by URL (login-gated)"
[6]: https://www.oracle.com/technetwork/database/availability/ebs-122-maa-whitepaper-4258573.pdf "E-Business Suite Release 12.2 Maximum Availability Architecture — Oracle White Paper"
[7]: https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/volumereplication.htm "Block Volume Replication — Oracle"
[8]: https://docs.oracle.com/en-us/iaas/Content/File/Tasks/FSreplication.htm "File System Replication — Oracle"
[9]: https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usingreplication.htm "Object Storage Replication — Oracle"
[10]: https://docs.oracle.com/en-us/iaas/recovery-service/doc/recovery-service-architecture.html "Recovery Service Technical Architecture — Oracle"
[11]: https://docs.oracle.com/en/solutions/implement-recovery-service-db-at-azure/index.html "Implement Oracle Database Autonomous Recovery Service with Oracle Database@Azure — Oracle"
[12]: https://docs.oracle.com/en-us/iaas/exadatacloud/doc/ecs-managing-db-backup-and-recovery.html "Manage Database Backup and Recovery on ExaDB-D — Oracle"
[13]: https://docs.oracle.com/en-us/iaas/recovery-service/doc/about-policy-locking.html "Using Retention Lock to Protect Backups — Oracle"
[14]: https://docs.oracle.com/en-us/iaas/releasenotes/changes/19e890da-7b15-4d55-a0b3-28058930a8f8/ "Backup and Restore from a Standby Database in a Data Guard Environment — OCI release note"
[15]: https://docs.oracle.com/en-us/iaas/recovery-service/doc/about-recovery-service.html "About Oracle Database Autonomous Recovery Service — Oracle"
[16]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/dr-plans-type.html "Types of Disaster Recovery Plans — OCI Full Stack DR"
[17]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf "NIST SP 800-34 Rev. 1 — Contingency Planning Guide for Federal Information Systems"
[18]: https://docs.oracle.com/en-us/iaas/Content/File/Tasks/fsreplication-creating-a-replication.htm "Creating a Replication — OCI File Storage"
[19]: #references "MOS Doc ID 134007.1 — unverifiable by URL (login-gated)"
[20]: https://www.pythian.com/blog/be-warned-cmclean-sql-is-dangerous/ "Be Warned: cmclean.sql Is Dangerous! — Pythian"
[21]: #references "MOS Doc ID 2617787.1 — unverifiable by URL (login-gated)"
[22]: https://mikedietrichde.com/2020/06/30/collection-of-ebs-upgrade-information-for-oracle-database-19c/ "Collection of EBS upgrade information for Oracle Database 19c and 26ai — Mike Dietrich"
[23]: http://ermanarslan.blogspot.com/2020/05/ebs-on-oracle-database-19c-supported.html "EBS on Oracle Database 19c — Erman Arslan's Oracle Blog"
[24]: #references "MOS Doc ID 1963472.1 — unverifiable by URL (login-gated)"
[25]: https://pdfcoffee.com/business-continuity-for-oracle-ebsr122-pdf-free.html "Business Continuity for Oracle EBS R12.2 — third-party copy on pdfcoffee.com"
