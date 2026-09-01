# 01 — Target DR Architecture

**Primary:** `us-ashburn-1` (IAD)  ·  **Secondary:** `us-phoenix-1` (PHX)
**Workload:** Oracle E-Business Suite on Exadata Database Service, Windows application/presentation tiers.

---

## 1. Stated assumptions

These drive the design. Confirm or correct before build — items marked **[MATERIAL]** change the design if wrong.

| # | Assumption | Impact if wrong |
|---|---|---|
| A1 | EBS **12.2.x** (dual filesystem fs1/fs2, WebLogic-based) | **[MATERIAL]** 12.1 removes the online-patching FS split; simplifies §4.3 |
| A2 | Database is **19c** on **ExaDB-D** (Exadata Database Service on Dedicated Infrastructure), not Cloud@Customer | **[MATERIAL]** ExaCC changes networking, Data Guard setup, and Full Stack DR member support |
| A3 | EBS app tier runs on **Windows Server x64**, relinked with **MKS Toolkit** [45] (Doc ID 1330706.1 is the current 12.2-on-Windows note [1][2]; Cygwin appears only as an alternative in 12.1-era documentation, Doc ID 414992.1 [3][4], not in the current 12.2 tooling [45]) | Affects script language (PowerShell) and FSS mount strategy (§4.4) |
| A4 | "Visualization tier" = BI / reporting presentation layer (OBIEE, Discoverer, Power BI gateway, or similar) | **[MATERIAL]** If it means *virtualization* (Hyper-V / VMware / OCVS), §4.5 is replaced by an OCVS-based design |
| A5 | Database does **not** use Hybrid Columnar Compression (HCC) | If HCC is used, the standby storage must be Exadata, Oracle ZFS Storage Appliance, or Pillar Axiom/FS1 [5]. Whether HCC-compressed data becomes unreadable on unsupported storage is *(unverified: engineering judgement; no documentation found in this revision)* — validate before assuming a downgrade path to Base DB Service is closed |
| A6 | Cross-region traffic rides **DRG + Remote Peering Connection** over the OCI backbone (not FastConnect / Internet) | Changes bandwidth guarantee and redo transport tuning (§5.3) |
| A7 | Single production EBS instance (no multi-org split across regions) | Multi-instance changes the tiering map |

---

## 2. Architecture in one picture

```mermaid
flowchart TB
    USER([Users / Integrations]):::ext
    TM{{"OCI Traffic Management<br/>failover steering + health checks"}}:::ctrl
    USER --> TM

    subgraph IAD["🟢 us-ashburn-1 — PRIMARY · VCN 10.10.0.0/16"]
        direction TB
        LBI["Flexible Load Balancer"]:::net
        subgraph IADAPP["Windows tiers — running"]
            direction LR
            WEBI["WIN-EBSWEB01/02<br/><i>Web / Forms</i>"]:::win
            CMI["WIN-EBSCM01<br/><i>Concurrent Mgr · Workflow · Admin</i>"]:::win
            BII["WIN-BI01<br/><i>Visualization / BI</i>"]:::win
        end
        DB1[("ExaDB-D · EBSPROD_IAD<br/><b>PRIMARY</b>")]:::dbp
        DB2[("ExaDB-D · EBSPROD_IAD2<br/>SYNC standby · AD-2")]:::dbs
        OBS(["FSFO Observer · AD-3"]):::ctrl
        LBI --> WEBI --> DB1
        CMI --> DB1
        BII --> DB1
        DB1 -- "SYNC ~0.5 ms · RPO 0" --> DB2
        OBS -.-> DB1
        OBS -.-> DB2
    end

    subgraph PHX["🟡 us-phoenix-1 — STANDBY · VCN 10.20.0.0/16"]
        direction TB
        LBP["Flexible Load Balancer"]:::net
        subgraph PHXAPP["Windows tiers — same FQDNs, stopped"]
            direction LR
            WEBP["WIN-EBSWEB01/02"]:::winoff
            CMP["WIN-EBSCM01"]:::winoff
            BIP["WIN-BI01<br/><i>reads ADG read-only</i>"]:::win
        end
        DB3[("ExaDB-D · EBSPROD_PHX<br/>Active Data Guard<br/>min OCPU floor")]:::dbs
        LBP -.-> WEBP -.-> DB3
        CMP -.-> DB3
        BIP -- "read-only reporting" --> DB3
    end

    TM ==> LBI
    TM -. "on failover" .-> LBP
    DB1 == "ASYNC redo · ~60-70 ms RTT<br/>DRG ↔ Remote Peering Connection" ==> DB3

    FSDR{{"OCI Full Stack Disaster Recovery<br/>DR Protection Group peer pair<br/>switchover · failover · drill"}}:::ctrl
    FSDR -.orchestrates.-> IAD
    FSDR -.orchestrates.-> PHX

    classDef ext fill:#e8eaf6,stroke:#5c6bc0,stroke-width:2px,color:#1a237e
    classDef net fill:#e0f2f1,stroke:#00897b,stroke-width:2px,color:#004d40
    classDef win fill:#e3f2fd,stroke:#1976d2,stroke-width:2px,color:#0d47a1
    classDef winoff fill:#f5f5f5,stroke:#9e9e9e,stroke-width:2px,stroke-dasharray:4 3,color:#616161
    classDef dbp fill:#c8e6c9,stroke:#2e7d32,stroke-width:3px,color:#1b5e20
    classDef dbs fill:#fff8e1,stroke:#f9a825,stroke-width:2px,color:#e65100
    classDef ctrl fill:#f3e5f5,stroke:#8e24aa,stroke-width:2px,color:#4a148c
```

**Reading the diagram:** solid heavy edges are the live production path; dashed edges activate only on failover. The BI tier is the exception — it reads the Phoenix standby *during normal operations*, which is what keeps the standby continuously proven (§4.5).

---

## 3. Why three Data Guard members, not two

**Oracle states that Ashburn↔Phoenix latency "exceeds 50 ms RTT" [7].** The ~60–70 ms figure used elsewhere in this plan is a representative estimate, not an Oracle-published number *(unverified: engineering judgement; no documentation found in this revision)* — measure your own. Synchronous redo transport at that latency adds the full RTT to every commit under Maximum Availability protection mode [6] — it will not survive an EBS period close or a large Order Management batch. Measure and record your actual RTT in `evidence/latency-baseline.md` before committing to any RPO number.

So the design splits the two jobs, using Oracle Data Guard's Maximum Availability (SYNC) and Maximum Performance (ASYNC) protection modes [6]:

| Member | Region | Mode | Purpose | RPO |
|---|---|---|---|---|
| `EBSPROD_IAD` | Ashburn AD-1 | Primary | Production | — |
| `EBSPROD_IAD2` | Ashburn AD-2 | **SYNC** (Max Availability) + FSFO | Local HA — AD or rack failure. Automatic. | **0** |
| `EBSPROD_PHX` | Phoenix | **ASYNC** (Max Performance), Active Data Guard | Regional DR. Orchestrated, never automatic. | seconds |

An **Oracle Data Guard Far Sync instance** in Ashburn AD-3 is a valid alternative to `EBSPROD_IAD2` if you want zero-data-loss *to Phoenix* without a full second standby — a far sync instance "receives redo into standby redo logs (SRLs), and archives those SRLs to local archived redo logs" but "does not have user data files, cannot be opened for access, cannot run redo apply, and can never function in the primary role" [8], and requires an Oracle Active Data Guard licence [8][5]. It costs less (no Exadata storage) but gives no local failover target. Choose `EBSPROD_IAD2` if local HA matters; choose Far Sync if only cross-region RPO=0 matters.

**Fast-Start Failover (FSFO) requires an observer** running on a host separate from the primary and standby [9]; Oracle's best practice is to place it "at a third site or third data center so that the primary, observer, and standby have isolated power, server, storage, and network infrastructure" [10]. This plan's FSFO observer sits in Ashburn AD-3 — a third availability domain, not a third region; Oracle's stronger recommendation is a genuinely separate site.

**Automatic failover is deliberately scoped to Ashburn only.** Cross-region FSFO invites split-brain and, more practically, promotes a database whose Windows app tier is not yet running — which buys nothing. Cross-region promotion is always an orchestrated Full Stack DR plan execution. Consistent with that, this plan leaves **Full Stack DR's own "Automatic DR" toggle disabled** for the Phoenix Data Guard member: that feature would otherwise trigger an automated Full Stack DR plan execution whenever the Data Guard configuration changes role [11], which is exactly the automatic cross-region promotion this design rejects.

---

## 4. Per-tier replication design

### 4.1 Database — Exadata

- **Transport:** **Oracle Data Guard** redo transport, with redo transport compression enabled on the PHX leg — this requires the **Oracle Advanced Compression** option licence, since "Data Guard Redo Transport Compression" is one of the features included under Oracle Advanced Compression [5]. The Broker's `RedoRoutes` property overrides the default redo-routing behaviour [18]; this plan does not rely on cascaded routing, since Oracle's page describing `RedoRoutes` does not use the word "cascade" for this configuration.
- **Apply:** **Oracle Active Data Guard** real-time apply in PHX, which requires an Active Data Guard licence [12][5]. This buys two things beyond DR — automatic block repair, and a read-only reporting source for the visualization tier (§4.5).
- **Broker:** **Oracle Data Guard Broker** (`dgmgrl`) manages the whole configuration. The **Fast-Start Failover (FSFO) Observer** runs in Ashburn AD-3 on a small always-on VM and targets `EBSPROD_IAD2` **only** (§3).
- **Backups (independent failure domain):** **Oracle Database Autonomous Recovery Service, deployed in both regions** — the Ashburn service protects the primary, and the Phoenix service protects the Phoenix standby (backups on a standby-role database are supported [16]). Real-time redo transport to Recovery Service is an extra-cost option that gets RPO "near the last sub-second" [13]. Recovery Service does not offer a documented cross-region backup-copy feature; Oracle's stated pattern for cross-region protection is "use Oracle Data Guard to replicate databases from primary to standby region and backup each region with local recovery service" [15], with each region's backups replicating for high availability within that region and restorable "to any availability domain, zone, or region" [13]. So the Phoenix service holds an independent, immutable backup of the *standby*, not a copy of the Ashburn backups — the ransomware / logical-corruption answer that Data Guard alone does not give you, since Data Guard faithfully replicates a `DELETE`. Enable retention lock (immutability, minimum 14-day lock delay) [14]. **After any switchover or failover, automatic backups are disabled on the new standby and must be explicitly re-enabled on the new primary** [17].
- **Oracle Flashback Database ON** on the primary and both standbys. Flashback is required for the Broker's `REINSTATE DATABASE` to succeed after a failover — "Flashback Database must have been enabled on the database prior to the failover" [9] — which is what makes failback fast (RB-03). It is *not* a prerequisite for snapshot-standby drills: those need only a Fast Recovery Area, since "it is not necessary for flashback database to be enabled" to convert a physical standby to a snapshot standby [12] (RB-04). Keep Flashback on regardless, since reinstate is the design's failback path.

> **HCC check.** Run `scripts/dataguard/check-hcc.sql` before sizing the standby. If any EBS or custom segment uses HCC, the PHX standby must be Exadata — a Base Database Service standby cannot query those segments.

### 4.2 Windows EBS application tier — Block Volumes

Two mechanisms, used for different things:

| What | Mechanism | Why |
|---|---|---|
| OS + EBS binaries (`$APPL_TOP`, fs1/fs2, WebLogic domain) | **OCI Block Volume — Volume Group Replication** (cross-region) | All replicas in the group "are activated from the same coordinated synchronization point" [19] — a group-level guarantee across boot + all data volumes. Individually-replicated volumes are **not** mutually consistent — always use a volume group. |
| Rebuild-from-scratch path | **OCI Compute Custom Images** plus **Instance Configurations** | Faster and cleaner for a Tier-2 cold rebuild; also your drift-recovery path if a replica is corrupt. There is no single "copy image to another region" operation — it is export the image to Object Storage, copy the object to the destination region's bucket, then import it there [20]. |
| Inbound/outbound interface landing directories | Volume group replication **and** Object Storage staging (§4.4) | Interface files are the most common source of Work Recovery Time — see `docs/02-mtd-tiers.md` |

**Operational note.** A volume group replica in PHX is not directly attachable. Failover requires *activating* the replica into a real volume group first, which takes minutes and is a scripted step (`scripts/oci/activate-volume-group.sh`). Budget for it in RTO. Instance Configurations are fine for rebuilding compute, but **Full Stack DR does not support compute instances that are attached to an instance pool** [21] — if pool-managed scaling is in use for any Windows tier, that tier needs a Full Stack DR compute member design that avoids instance pools.

### 4.3 EBS 12.2 dual filesystem

EBS 12.2 online patching keeps two filesystems (`fs1`, `fs2`) — a run edition and a patch edition — plus `fs_ne` (non-editioned) [22]. **All three must be replicated.** A standby that has only the run edition will come up, but the next `adop` cycle will fail and you will have no patching capability in DR.

**Freeze rule: do not fail over mid-`adop` cycle.** If an online patching cycle is open when disaster strikes, the failover runbook has an `adop -abort` + `fs_clone` recovery branch, using the documented `adop -status`, `adop phase=abort`, and `adop phase=fs_clone` commands [22] (RB-02 §7). Track cycle state on the health dashboard.

### 4.4 Shared file systems — FSS vs Windows-native

A genuine decision point, because **OCI File Storage supports the NFSv3 protocol** [23] and Windows NFS client support (the Windows Client for NFS, accessing exports anonymously via `AnonymousUid`/`AnonymousGid` mapping under AUTH_SYS) [27] is workable but has UID-mapping friction and no NFSv4 semantics.

| Option | Use when | Cross-region mechanism | RPO |
|---|---|---|---|
| **A. OCI File Storage (FSS) — File System Replication**, mounted by the Windows *Client for NFS* [27] | Shared EBS directories that are read-mostly; any Linux-side consumers | **FSS File System Replication** (cross-region, snapshot-delta based) [24] | Interval-driven — minimum 15 minutes, default 60 minutes if none is specified [24][25]. |
| **B. Windows File Server + Windows Server Storage Replica** | Heavy SMB write workloads, ACL-sensitive shares | **Windows Server Storage Replica**, asynchronous, cross-region | seconds–minutes |
| **C. Object Storage as the interchange** | Batch interface files, EDI drops, archive | **OCI Object Storage — Replication Policy** | minutes |

**Recommendation: A for EBS shared directories, C for all batch interchange, B only where an application genuinely demands SMB semantics.** Option B is powerful but adds a Windows cluster you must patch, license, and DR-test independently — the highest-maintenance choice on this page.

> **FSS replication targets are read-only** while the replication resource exists [24]. Making one writable at failover means exporting it, which requires deleting the replication resource (or, if the source region is unreachable, deleting the replication target instead) [24][26]. **Once a target has been exported, re-establishing replication requires a full base copy**; a target that was never exported and had no snapshots created or deleted on it "can avoid a full base copy" and be reused directly [25]. This is a one-way door per failover event, once the target has been exported. Script it (`scripts/oci/fss-failover.sh`) and account for the re-baseline window in the failback plan.

### 4.5 Visualization / BI tier

Point it at the **Active Data Guard standby in PHX for read-only reporting during normal operations.** This turns a cold asset into a working one and continuously proves the standby is healthy and queryable — the best DR test is the one that runs every day.

EBS caveat: Oracle's EBS 12.2 MAA white paper states that "the Oracle E-Business Suite supports a limited set of Oracle Active Data Guard functions" for reporting [29]. The documented reference for the restrictions is My Oracle Support Doc ID 1944539.1, *Using Active Data Guard Reporting with Oracle E-Business Suite Release 12.2 and an Oracle 11g or 12c Database* [28][29] — for a 19c database, the equivalent note is Doc ID 2608030.1, *Using Active Data Guard Reporting with Oracle E-Business Suite Release 12.2 and Oracle Database 19c* [30][31][32]. Do not simply repoint the standard EBS reporting stack at the standby and expect it to work; validate against the applicable note for your exact database and EBS patch level.

---

## 5. Network and naming — the single biggest RTO lever

### 5.1 Identical hostnames across regions

**Design decision: the PHX app tier uses the same FQDNs and hostnames as IAD, resolved to region-local IPs by split-horizon private DNS.**

This matters more than any other choice in this document. EBS bakes hostnames into context files, `FND_NODES`, WebLogic configs, and profile options. If hostnames change at failover, Oracle's documented business-continuity sequence for a role transition is to purge `FND_NODES` and run AutoConfig on every tier: "Clean out the FND_NODES table by running the following command in SQL*Plus as the APPS user: `SQL> execute fnd_conc_clone.setup_clean;`", then run AutoConfig on the database tier, then "run AutoConfig on the middle tier for both RUN and PATCH file systems" [29]. The identical-hostnames pattern this plan uses instead — resolving the same FQDNs to region-local IPs — is documented by Oracle as "logical host names" for EBS 12.2 business continuity, My Oracle Support Doc ID 2246690.1 [33][29].

```sql
EXEC FND_CONC_CLONE.SETUP_CLEAN;   -- purge FND_NODES
-- then AutoConfig on the DB tier, then AutoConfig on every app tier node
```

That path is **~3–5 hours** *(unverified: engineering judgement; no documentation found in this revision)*. Keeping hostnames stable reduces app-tier recovery to *starting the services* — **~20–40 minutes** *(unverified: engineering judgement; no documentation found in this revision)*. The design therefore uses:

- Different VCN CIDRs (10.10/16 vs 10.20/16) — **required**, because both must be routable simultaneously for Data Guard
- **Identical hostnames** via OCI Private DNS zones with region-scoped views
- TNS aliases that resolve region-locally, so context files never change

### 5.2 External entry point

**OCI Traffic Management Steering Policies** — **Failover** policy type — with **OCI Health Checks**: "If the primary answer is unhealthy, DNS traffic is automatically steered to the secondary answer" [34]. Keep TTL low (30–60 s) — but remember client and corporate resolver caching means real-world DNS cutover is often 5–15 minutes regardless of TTL *(unverified: engineering judgement; no documentation found in this revision)*. Budget that into RTO; do not assume TTL is the whole story.

### 5.3 Redo transport tuning

Size TCP buffers from the bandwidth-delay product:

```
BDP (bytes) = bandwidth (bits/s) / 8 * RTT (s)
Example: 1 Gbps * 0.065 s = 8.1 MB  ->  SEND_BUF_SIZE / RECV_BUF_SIZE ~= 3 * BDP ~= 24 MB
```

The minimum recommended socket buffer size is 3× the bandwidth-delay product [10]. Also set `SDU=65535` on both ends — this is Oracle's MAA-recommended value specifically "for synchronous transport only" [10], not the 19c protocol maximum, which is 2,097,152 bytes [35] — enable redo transport compression on the PHX leg (Advanced Compression option licence required, §4.1 [5]), and size standby redo logs identical to online redo logs with one extra log group per redo thread [36]. See `scripts/dataguard/tnsnames-tuning.md`.

---

## 6. Orchestration — OCI Full Stack Disaster Recovery

Full Stack DR (FSDR) is the native orchestrator, and it is how the "spin up and tear down" requirement is answered.

- **DR Protection Group (DRPG)** in each region, associated as a peer pair.
- **Members:** Full Stack DR supports 11 native member types, including compute instances, volume groups, load balancers/network load balancers, Oracle databases (Base Database Service and Exadata Database Service on Dedicated Infrastructure), file systems, **Object Storage buckets**, Autonomous Database, OKE clusters, MySQL DB systems, and Integration instances [37]. **Object Storage is a native member type with built-in plan groups** — "Object Storage Bucket - Delete Replication (Primary)" and "Object Storage Bucket - Setup Reverse Replication (Standby)" [38] — it does not require a user-defined step. This plan also uses **user-defined steps** for EBS-specific logic.
- **Plans:** Switchover, Failover, **Start Drill**, **Stop Drill** [44]. The drill plans are the tear-down-able DR environment.
- **User-defined steps** run your EBS logic — stop/start services, `cmclean.sql`, AutoConfig where needed — via the **Oracle Cloud Agent Run Command plugin**, or by invoking an Oracle Function [39]. On Windows, a Run Command script executes in a batch shell by default; to run it under PowerShell, the script's first line must be `#ps1` [40]. Plain-text scripts uploaded directly are capped at 4 KB — larger scripts must be staged in Object Storage [40]. **The Run Command plugin must be enabled and healthy on every Windows instance, or plan execution fails at that step.** Verify it in prechecks, every time.
- **The Data Guard member supports only one standby** of a Data Guard configuration — "Data Guard allows you to configure multiple standby database. However, Full Stack DR only supports one of these standby databases" [43]. That matches this design's single-Phoenix-standby topology and rules out adding a second FSDR-orchestrated standby without redesigning around it. **Automatic DR stays off** on the Data Guard member, for the reasons given in §3 [11].
- **Full Stack DR is a charged service**, billed monthly on the allocated OCPU/ECPU (or OIC message packs) of compute, database, OKE, and Integration members — whether running or stopped — with no additional charge for block, file, object storage, load balancer, or networking members [42]. Budget the always-on Windows and database members accordingly.
- Grant FSDR access via dynamic groups + policies; send plan execution logs to a dedicated Object Storage bucket reserved exclusively for that DR Protection Group's logs [41].

See `docs/03-replication-matrix.md` for the full member-to-mechanism mapping, and `runbooks/` for executable procedures.

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. MOS Doc ID 1330706.1, Oracle. Unverifiable by URL: login-gated (My Oracle Support). Title corroborated only by [2].
2. *Oracle E-Business Suite Installation Guide: Using Rapid Install, Release 12.2* (title-listing page), Oracle, current, accessed 2026-09-01.
   <https://docs.oracle.com/cd/E26401_01/doc.122/e22950/T422699i4773.htm> — Supports: corroborates the titles/IDs of MOS Doc ID 1330701.1 (Linux) and 1330706.1 (Windows) (A3).
3. MOS Doc ID 414992.1, *Using Cygwin to Maintain Oracle E-Business Suite Release 12 on Windows*, Oracle. Unverifiable by URL: login-gated (My Oracle Support). Title corroborated only by [4].
4. *Oracle E-Business Suite Installation Guide: Using Rapid Install, Release 12.1*, Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/cd/E18727_01/doc.121/e12842/T422699i4773.htm> — Supports: "Windows users can employ software from Cygwin as an alternative to MKS Toolkit... My Oracle Support Knowledge Document 414992.1" (A3).
5. *Database Licensing Information User Manual*, Oracle Database 19c, Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html> — Supports: HCC-eligible storage list (A5); Data Guard Redo Transport Compression requires the Advanced Compression option (§4.1, §5.3); Far Sync and Active Data Guard require the Active Data Guard licence (§3, §4.1).
6. *Oracle Data Guard Protection Modes*, Data Guard Concepts and Administration 19c, Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-protection-modes.html> — Supports: Maximum Availability (SYNC) and Maximum Performance (ASYNC) protection-mode mechanics (§3).
7. *Set Up FMW Stretched Clusters*, Oracle Solutions (G49655-02, March 2026), accessed 2026-09-01.
   <https://docs.oracle.com/en/solutions/fmw-stretched-clusters/set-fmw-stretched-clusters1.html> — Supports: "the latency between these regions [Ashburn and Phoenix] exceeds 50 ms RTT" (§3).
8. *Using Far Sync Instances*, Data Guard Concepts and Administration 19c, Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/creating-oracle-data-guard-far-sync-instance.html> — Supports: far sync instance behaviour and Active Data Guard licence requirement (§3).
9. *Switchover and Failover Operations*, Oracle Data Guard Broker 19c (E96245-04), Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html> — Supports: FSFO observer must run on a separate host (§3); Flashback Database must be enabled before the failover for REINSTATE to succeed (§4.1).
10. *High Availability Overview and Best Practices*, Oracle Database 19c (F23691-56, July 2026), Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en/database/oracle/oracle-database/19/haovw/high-availability-overview-and-best-practices.pdf> — Supports: observer sited at a third data center as best practice (§3); SDU=65535 as the MAA-recommended value "for Synchronous Transport Only", and 3×BDP socket-buffer sizing (§5.3).
11. *Configure Automatic DR Plan Execution*, OCI Full Stack Disaster Recovery documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/configure-automaticdr.html> — Supports: Automatic DR can trigger a plan execution on a Data Guard role change; this design leaves it disabled (§3, §6).
12. *Managing Physical and Snapshot Standby Databases*, Data Guard Concepts and Administration 19c, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/managing-oracle-data-guard-physical-standby-databases.html> — Supports: Active Data Guard real-time query requires an Active Data Guard licence; a snapshot standby needs a Fast Recovery Area and "it is not necessary for flashback database to be enabled" (§4.1).
13. *Recovery Service Technical Architecture*, Oracle Database Autonomous Recovery Service documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/recovery-service/doc/recovery-service-architecture.html> — Supports: real-time protection is an extra-cost option with RPO "near the last sub-second"; backups restorable "to any availability domain, zone, or region" (§4.1).
14. *Using Retention Lock to Protect Backups*, Oracle Database Autonomous Recovery Service documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/recovery-service/doc/about-policy-locking.html> — Supports: minimum 14-day retention-lock delay (§4.1).
15. *Implement Oracle Database Autonomous Recovery Service with Oracle Database@Azure*, Oracle Solutions playbook (G24007-01, January 2025), accessed 2026-09-01.
    <https://docs.oracle.com/en/solutions/implement-recovery-service-db-at-azure/index.html> — Supports: "For cross region backups, use Oracle Data Guard to replicate databases from primary to standby region and backup each region with local recovery service." (§4.1).
16. *Manage Database Backup and Recovery on Exadata Database Service on Dedicated Infrastructure*, Oracle Cloud Infrastructure Documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/exadatacloud/doc/ecs-managing-db-backup-and-recovery.html> — Supports: "You can enable the Automatic Backup feature on a database with the standby role in a Data Guard association." (§4.1).
17. *Backup and Restore from a Standby Database in a Data Guard Environment*, OCI release note, August 24, 2023, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/releasenotes/changes/19e890da-7b15-4d55-a0b3-28058930a8f8/> — Supports: backups are disabled on the new standby / disabled standby after a switchover or failover (§4.1).
18. *Oracle Data Guard Broker Properties*, Oracle Data Guard Broker 19c (E96245-04), Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/oracle-data-guard-broker-properties.html> — Supports: the RedoRoutes property overrides the default redo-routing behaviour (§4.1).
19. *Replicating Volume Groups*, Oracle Cloud Infrastructure Documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/volumegroupreplication.htm> — Supports: "Activating the volume group replica ensures that all replicas are activated from the same coordinated synchronization point." (§4.2).
20. *Importing and Exporting Custom Images*, Oracle Cloud Infrastructure Documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/imageimportexport.htm> — Supports: cross-region image copy is export → object copy → import, not a single operation (§4.2).
21. *Add a Compute Instance to a Disaster Recovery Protection Group*, OCI Full Stack Disaster Recovery documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-compute-instance.html> — Supports: "Full Stack DR does not support the compute instances that are attached to an instance pool." (§4.2).
22. *Patching Procedures*, Oracle E-Business Suite Maintenance Guide, Release 12.2, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/cd/E26401_01/doc.122/e22954/T202991T531065.htm> — Supports: fs1/fs2/fs_ne dual-filesystem design; `adop -status`, `adop phase=abort`, `adop phase=fs_clone` (§4.3).
23. *Overview of File Storage*, Oracle Cloud Infrastructure Documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/Content/File/Concepts/filestorageoverview.htm> — Supports: "The File Storage service supports the Network File System version 3.0 (NFSv3) protocol." (§4.4).
24. *File System Replication*, Oracle Cloud Infrastructure Documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/Content/File/Tasks/FSreplication.htm> — Supports: cross-region snapshot-delta replication; target file system is read-only while replication exists; minimum replication interval is 15 minutes (§4.4).
25. *Creating a Replication*, Oracle Cloud Infrastructure File Storage documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/Content/File/Tasks/fsreplication-creating-a-replication.htm> — Supports: default replication interval of 60 minutes; a never-exported target "can avoid a full base copy" on reuse (§4.4).
26. *Deleting a Replication*, Oracle Cloud Infrastructure File Storage documentation, Oracle, accessed 2026-09-01.
    <https://docs.cloud.oracle.com/en-us/Content/File/Tasks/delete-replication.htm> — Supports: deleting the replication resource (or, if the source is unavailable, the replication target) is how a target file system becomes exportable (§4.4).
27. *Mounting File Systems From Windows Instances*, Oracle Cloud Infrastructure Documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/Content/File/Tasks/mountingwindowsos.htm> — Supports: Windows Client for NFS and AnonymousUid/AnonymousGid mapping under AUTH_SYS (§4.4).
28. MOS Doc ID 1944539.1, *Using Active Data Guard Reporting with Oracle E-Business Suite Release 12.2 and an Oracle 11g or 12c Database*, Oracle. Unverifiable by URL: login-gated (My Oracle Support). Title corroborated only by [29], which cites it.
29. *E-Business Suite Release 12.2 Maximum Availability Architecture*, Oracle White Paper, January 2018, accessed 2026-09-01.
    <https://www.oracle.com/technetwork/database/availability/ebs-122-maa-whitepaper-4258573.pdf> — Supports: "the Oracle E-Business Suite supports a limited set of Oracle Active Data Guard functions", citing Doc ID 1944539.1 by title (§4.5); the FND_NODES purge + AutoConfig sequence for a role transition, steps 10–13 (§5.1); cites Doc ID 2246690.1 by title (§5.1).
30. MOS Doc ID 2608030.1, *Using Active Data Guard Reporting with Oracle E-Business Suite Release 12.2 and Oracle Database 19c*, Oracle. Unverifiable by URL: login-gated (My Oracle Support). Title corroborated only by [31] and [32].
31. *Collection of EBS upgrade information for Oracle Database 19c and 26ai*, Mike Dietrich, personal blog, 2020-06-30, accessed 2026-09-01.
    <https://mikedietrichde.com/2020/06/30/collection-of-ebs-upgrade-information-for-oracle-database-19c/> — Supports: corroborates the title and ID of Doc ID 2608030.1 only (§4.5).
32. *EBS on Oracle Database 19c — supported*, Erman Arslan's Oracle Blog, 2020-05-02, accessed 2026-09-01.
    <http://ermanarslan.blogspot.com/2020/05/ebs-on-oracle-database-19c-supported.html> — Supports: corroborates the title and ID of Doc ID 2608030.1 only (§4.5).
33. MOS Doc ID 2246690.1, *Business Continuity for Oracle E-Business Suite Release 12.2 using Logical Host Names*, Oracle. Unverifiable by URL: login-gated (My Oracle Support). Title corroborated only by [29], which cites it.
34. *Overview of Traffic Management*, Oracle Cloud Infrastructure Documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/Content/TrafficManagement/Concepts/overview.htm> — Supports: FAILOVER policy type with Health Checks steering traffic to a secondary answer (§5.2).
35. *Parameters for the sqlnet.ora File*, Oracle Net Services Reference 19c, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en/database/oracle/oracle-database/19/netrf/parameters-for-the-sqlnet.ora.html> — Supports: DEFAULT_SDU_SIZE valid range up to 2,097,152 bytes (§5.3).
36. *Redo Transport Services*, Data Guard Concepts and Administration 19c, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-redo-transport-services.html> — Supports: standby redo logs sized and grouped relative to online redo logs (§5.3).
37. *Add Members to a Disaster Recovery Protection Group*, OCI Full Stack Disaster Recovery documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-members-protection-group.html> — Supports: the 11 native DR Protection Group member types, including Object Storage buckets (§6).
38. *Default Order of DR Plan Groups*, OCI Full Stack Disaster Recovery documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/Order-of-dr-plan-groups.html> — Supports: built-in "Object Storage Bucket - Delete Replication (Primary)" and "Object Storage Bucket - Setup Reverse Replication (Standby)" plan groups (§6).
39. *Add User-Defined Plan Groups and Steps*, OCI Full Stack Disaster Recovery documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-user-defined-plan-groups.html> — Supports: user-defined steps run via Run Command or Oracle Functions (§6).
40. *Running Commands on an Instance*, Oracle Cloud Infrastructure Documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/runningcommands.htm> — Supports: Windows scripts run in a batch shell unless prefixed `#ps1`; 4 KB plain-text script limit (§6).
41. *Preparing Log Location for Operation Logs*, OCI Full Stack Disaster Recovery documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/object-storage-for-logs.html> — Supports: use a separate dedicated bucket reserved for one DR Protection Group's logs (§6).
42. *Full Stack DR Billing Details*, OCI Full Stack Disaster Recovery documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/billing-details.html> — Supports: monthly charges on allocated OCPU/ECPU of compute, database, OKE, and Integration members, running or stopped; no charge for storage, networking, or load balancer members (§6).
43. *Preparing Oracle Databases for Full Stack Disaster Recovery*, OCI Full Stack Disaster Recovery documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/prepare-database-disaster-recovery.html> — Supports: "Full Stack DR only supports one of these standby databases" (§6).
44. *Types of Disaster Recovery Plans*, OCI Full Stack Disaster Recovery documentation, Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/dr-plans-type.html> — Supports: Switchover, Failover, Start Drill, Stop Drill plan types (§6).
45. *Oracle E-Business Suite Installation Guide: Using Rapid Install, Release 12.2* (PDF, E22950-49, November 2025), Oracle, accessed 2026-09-01.
    <https://docs.oracle.com/cd/E26401_01/doc.122/e22950.pdf> — Supports: "UNIX Toolkit Directory (Windows) Location of MKS tools"; zero occurrences of "Cygwin" in the current 12.2 guide (A3).

### Unverified statements

The following statements are engineering judgement with no supporting documentation found in this revision:

- The ~60–70 ms IAD↔PHX figure is a representative estimate, not an Oracle-published number (§3).
- Whether HCC-compressed data becomes unreadable on non-Exadata storage (A5).
- The SETUP_CLEAN + AutoConfig path takes ~3–5 hours, and preserving hostnames reduces app-tier recovery to ~20–40 minutes (§5.1).
- Real-world DNS cutover is often 5–15 minutes regardless of TTL, due to client and resolver caching (§5.2).

[1]: #references "MOS Doc ID 1330706.1 — unverifiable by URL (login-gated)"
[2]: https://docs.oracle.com/cd/E26401_01/doc.122/e22950/T422699i4773.htm "Oracle E-Business Suite Installation Guide: Using Rapid Install, Release 12.2 — Oracle"
[3]: #references "MOS Doc ID 414992.1 — unverifiable by URL (login-gated)"
[4]: https://docs.oracle.com/cd/E18727_01/doc.121/e12842/T422699i4773.htm "Oracle E-Business Suite Installation Guide: Using Rapid Install, Release 12.1 — Oracle"
[5]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html "Database Licensing Information User Manual 19c — Oracle"
[6]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-protection-modes.html "Oracle Data Guard Protection Modes — Oracle"
[7]: https://docs.oracle.com/en/solutions/fmw-stretched-clusters/set-fmw-stretched-clusters1.html "Set Up FMW Stretched Clusters — Oracle"
[8]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/creating-oracle-data-guard-far-sync-instance.html "Using Far Sync Instances — Oracle"
[9]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html "Switchover and Failover Operations — Oracle Data Guard Broker 19c"
[10]: https://docs.oracle.com/en/database/oracle/oracle-database/19/haovw/high-availability-overview-and-best-practices.pdf "High Availability Overview and Best Practices — Oracle Database 19c"
[11]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/configure-automaticdr.html "Configure Automatic DR Plan Execution — OCI Full Stack DR"
[12]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/managing-oracle-data-guard-physical-standby-databases.html "Managing Physical and Snapshot Standby Databases — Oracle"
[13]: https://docs.oracle.com/en-us/iaas/recovery-service/doc/recovery-service-architecture.html "Recovery Service Technical Architecture — Oracle"
[14]: https://docs.oracle.com/en-us/iaas/recovery-service/doc/about-policy-locking.html "Using Retention Lock to Protect Backups — Oracle"
[15]: https://docs.oracle.com/en/solutions/implement-recovery-service-db-at-azure/index.html "Implement Oracle Database Autonomous Recovery Service with Oracle Database@Azure — Oracle"
[16]: https://docs.oracle.com/en-us/iaas/exadatacloud/doc/ecs-managing-db-backup-and-recovery.html "Manage Database Backup and Recovery on ExaDB-D — Oracle"
[17]: https://docs.oracle.com/en-us/iaas/releasenotes/changes/19e890da-7b15-4d55-a0b3-28058930a8f8/ "Backup and Restore from a Standby Database in a Data Guard Environment — OCI release note"
[18]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/oracle-data-guard-broker-properties.html "Oracle Data Guard Broker Properties — Oracle"
[19]: https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/volumegroupreplication.htm "Replicating Volume Groups — Oracle"
[20]: https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/imageimportexport.htm "Importing and Exporting Custom Images — Oracle"
[21]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-compute-instance.html "Add a Compute Instance to a Disaster Recovery Protection Group — Oracle"
[22]: https://docs.oracle.com/cd/E26401_01/doc.122/e22954/T202991T531065.htm "Patching Procedures — Oracle E-Business Suite Maintenance Guide, Release 12.2"
[23]: https://docs.oracle.com/en-us/iaas/Content/File/Concepts/filestorageoverview.htm "Overview of File Storage — Oracle"
[24]: https://docs.oracle.com/en-us/iaas/Content/File/Tasks/FSreplication.htm "File System Replication — Oracle"
[25]: https://docs.oracle.com/en-us/iaas/Content/File/Tasks/fsreplication-creating-a-replication.htm "Creating a Replication — OCI File Storage"
[26]: https://docs.cloud.oracle.com/en-us/Content/File/Tasks/delete-replication.htm "Deleting a Replication — OCI File Storage"
[27]: https://docs.oracle.com/en-us/iaas/Content/File/Tasks/mountingwindowsos.htm "Mounting File Systems From Windows Instances — Oracle"
[28]: #references "MOS Doc ID 1944539.1 — unverifiable by URL (login-gated)"
[29]: https://www.oracle.com/technetwork/database/availability/ebs-122-maa-whitepaper-4258573.pdf "E-Business Suite Release 12.2 Maximum Availability Architecture — Oracle White Paper"
[30]: #references "MOS Doc ID 2608030.1 — unverifiable by URL (login-gated)"
[31]: https://mikedietrichde.com/2020/06/30/collection-of-ebs-upgrade-information-for-oracle-database-19c/ "Collection of EBS upgrade information for Oracle Database 19c and 26ai — Mike Dietrich"
[32]: http://ermanarslan.blogspot.com/2020/05/ebs-on-oracle-database-19c-supported.html "EBS on Oracle Database 19c — Erman Arslan's Oracle Blog"
[33]: #references "MOS Doc ID 2246690.1 — unverifiable by URL (login-gated)"
[34]: https://docs.oracle.com/en-us/iaas/Content/TrafficManagement/Concepts/overview.htm "Overview of Traffic Management — Oracle"
[35]: https://docs.oracle.com/en/database/oracle/oracle-database/19/netrf/parameters-for-the-sqlnet.ora.html "Parameters for the sqlnet.ora File — Oracle Net Services Reference 19c"
[36]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-redo-transport-services.html "Redo Transport Services — Oracle"
[37]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-members-protection-group.html "Add Members to a Disaster Recovery Protection Group — Oracle"
[38]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/Order-of-dr-plan-groups.html "Default Order of DR Plan Groups — Oracle"
[39]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-user-defined-plan-groups.html "Add User-Defined Plan Groups and Steps — Oracle"
[40]: https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/runningcommands.htm "Running Commands on an Instance — Oracle"
[41]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/object-storage-for-logs.html "Preparing Log Location for Operation Logs — Oracle"
[42]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/billing-details.html "Full Stack DR Billing Details — Oracle"
[43]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/prepare-database-disaster-recovery.html "Preparing Oracle Databases for Full Stack Disaster Recovery — Oracle"
[44]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/dr-plans-type.html "Types of Disaster Recovery Plans — OCI Full Stack DR"
[45]: https://docs.oracle.com/cd/E26401_01/doc.122/e22950.pdf "Oracle E-Business Suite Installation Guide: Using Rapid Install, Release 12.2 (PDF) — Oracle"
