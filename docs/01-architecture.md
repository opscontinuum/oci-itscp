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
        subgraph IADAPP["Windows tiers — running, split across AD-1 and AD-2"]
            direction LR
            WEBI["IAD-EBSWEB01 (AD-1) · IAD-EBSWEB02 (AD-2)<br/><i>Web / Forms · logical names ebsweb01/02</i>"]:::win
            CMI["IAD-EBSCM01 (AD-1) · IAD-EBSCM02 (AD-2, stopped)<br/><i>Concurrent Mgr · Workflow · Admin</i>"]:::win
            BII["IAD-BI01 (AD-2)<br/><i>Visualization / BI</i>"]:::win
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
        subgraph PHXAPP["Windows tiers — own physical names, same EBS logical names, stopped"]
            direction LR
            WEBP["PHX-EBSWEB01/02<br/><i>ebsweb01/02</i>"]:::winoff
            CMP["PHX-EBSCM01/02<br/><i>ebscm01/02</i>"]:::winoff
            BIP["PHX-BI01 · always on<br/><i>reads ADG read-only</i>"]:::win
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

**Reading the diagram:** solid heavy edges are the live production path; dashed edges activate only on failover. The Windows tiers in Ashburn are split across two availability domains so that the local Data Guard leg protects a service someone can reach, not only a database (§3). Physical computer names are unique per region and AD; EBS itself is configured with logical host names that are the same in both regions (§5.1). The BI tier is the exception to "stopped" — PHX-BI01 is always on and reads the Phoenix standby *during normal operations*, which is what keeps the standby continuously proven (§4.5).

---

## 3. Why three Data Guard members, not two

**Oracle states that Ashburn↔Phoenix latency "exceeds 50 ms RTT" [7].** The ~60–70 ms figure used elsewhere in this plan is a representative estimate, not an Oracle-published number *(unverified: engineering judgement; no documentation found in this revision)* — measure your own. Synchronous redo transport at that latency adds the full RTT to every commit under Maximum Availability protection mode [6] — it will not survive an EBS period close or a large Order Management batch. Measure and record your actual RTT in `evidence/latency-baseline.md` before committing to any RPO number.

So the design splits the two jobs, using Oracle Data Guard's Maximum Availability (SYNC) and Maximum Performance (ASYNC) protection modes [6]:

| Member | Region | Mode | Purpose | RPO |
|---|---|---|---|---|
| `EBSPROD_IAD` | Ashburn AD-1 | Primary | Production | — |
| `EBSPROD_IAD2` | Ashburn AD-2 | **SYNC** (Max Availability) + FSFO | Local HA — AD or rack failure. Automatic. | **0 while synchronized** [36][10] |
| `EBSPROD_PHX` | Phoenix | **ASYNC** (Max Performance), Active Data Guard | Regional DR. Orchestrated, never automatic. | transport lag; target < 30 s, measured [6] |

Both standbys are created through the OCI Data Guard Group (`oci db database create-standby-database`) so that the control plane and Full Stack DR see all three members; a standby built outside the control plane is invisible to Full Stack DR prechecks [43].

**The local leg protects a service, not only a database.** The Windows tiers are split across Ashburn AD-1 and AD-2 (§2), with the load balancer spanning both, so that after a Fast-Start Failover to `EBSPROD_IAD2` the AD-2 web node and the stopped concurrent-manager twin `IAD-EBSCM02` can carry the service. Without that split an AD-1 loss would promote a database that no application node can reach, which is the same objection this plan makes to cross-region automatic failover below.

**RPO 0 is conditional, and the runbooks say so.** Under Maximum Availability the primary "will wait a maximum of NET_TIMEOUT seconds for an acknowledgment from any of the standby databases, after which it will signal commit success to the application and move to the next transaction" [10]; Oracle recommends that NET_TIMEOUT "be specified whenever the synchronous redo transport mode is used, so that the maximum duration of a redo source database stall caused by a redo transport fault can be precisely controlled" [36]. This plan sets the Broker `NetTimeout` on `EBSPROD_IAD2` explicitly (value measured for the same-region path; `scripts/dataguard/tnsnames-tuning.md` §4). Once the standby is unsynchronized, fast-start failover cannot occur: "If the protection mode is maximum availability or maximum protection and the target standby database was not synchronized with the primary database at the time the primary database failed" [9]. The monitoring therefore alarms on the unsynchronized state (`docs/04-monitoring.md` §2), and every RPO 0 claim in this plan means "while `EBSPROD_IAD2` is synchronized and Ashburn is primary".

**Fast-start failover constrains the runbooks.** While fast-start failover is enabled, "a switchover can be performed only to the pre-specified target standby database" and a manual failover "can only be performed to the current target standby database" [9]. A planned switchover to Phoenix (RB-01) therefore first drops the protection mode to Maximum Performance, sets `EBSPROD_IAD2` to ASYNC and disables fast-start failover; an unplanned failover to Phoenix (RB-02) issues `DISABLE FAST_START FAILOVER FORCE` from Phoenix, the form Oracle documents "when the network between the primary and target standby databases is disconnected or when the database upon which the command is received does not have a connection with the primary database" [46]. Oracle's own guidance for a configuration whose protection mode cannot be honoured after the transition is that "the protection level must be dropped to Maximum Performance prior to a switchover (planned event) as the level must be enforceable on the target in order to perform the transition" [10]. **While Phoenix is primary there is no synchronous standby, so the database RPO is the ASYNC transport lag to Ashburn until failback restores Maximum Availability (RB-03).**

An **Oracle Data Guard Far Sync instance** in Ashburn AD-3 is a valid alternative to `EBSPROD_IAD2` if you want zero-data-loss *to Phoenix* without a full second standby — a far sync instance "receives redo into standby redo logs (SRLs), and archives those SRLs to local archived redo logs" but "does not have user data files, cannot be opened for access, cannot run redo apply, and can never function in the primary role" [8], and requires an Oracle Active Data Guard licence [8][5]. It costs less (no Exadata storage) but gives no local failover target, and a far sync instance cannot be a fast-start failover target [18]. Choose `EBSPROD_IAD2` if local HA matters; choose Far Sync if only cross-region RPO 0 matters.

**Fast-Start Failover (FSFO) requires an observer** running on a host separate from the primary and standby [9]; Oracle's best practice is to place it "at a third site or third data center so that the primary, observer, and standby have isolated power, server, storage, and network infrastructure" [10], while also stating that "in an ideal state fast-start failover is deployed with the primary, standby, and observer, each within their own availability domain (AD) or data center; however, configurations that only use two availability domains, or even a single availability domain, must be supported" [10]. This plan's observer sits in Ashburn AD-3.

**Automatic failover is deliberately scoped to Ashburn only.** The reason is not split-brain — observer fencing and the Broker's fast-start failover protections exist precisely to prevent it, and Oracle documents cross-region fast-start failover with a longer threshold "over WAN" [10]. The reason is that a cross-region automatic promotion would produce a primary whose Windows application tier is stopped and whose storage replicas are not yet activated — a promoted database nobody can use, with the failback cost of `docs/03-replication-matrix.md` §2 already incurred. Cross-region promotion is always an orchestrated Full Stack DR plan execution. Consistent with that, this plan leaves **Full Stack DR's own "Automatic DR" toggle disabled** for the Phoenix Data Guard member: that feature would otherwise trigger an automated Full Stack DR plan execution whenever the Data Guard configuration changes role [11].

---

## 4. Per-tier replication design

### 4.1 Database — Exadata

- **Transport:** **Oracle Data Guard** redo transport, with redo transport compression enabled on the PHX leg — this requires the **Oracle Advanced Compression** option licence, since "Data Guard Redo Transport Compression" is one of the features included under Oracle Advanced Compression [5]. The Broker's `RedoRoutes` property overrides the default redo-routing behaviour [18]; this plan does not rely on cascaded routing, since Oracle's page describing `RedoRoutes` does not use the word "cascade" for this configuration.
- **Apply:** **Oracle Active Data Guard** real-time apply in PHX, which requires an Active Data Guard licence [12][5]. This buys two things beyond DR — automatic block repair, and a read-only reporting source for the visualization tier (§4.5).
- **Broker:** **Oracle Data Guard Broker** (`dgmgrl`) manages the whole configuration. The **Fast-Start Failover (FSFO) Observer** runs in Ashburn AD-3 on a small always-on VM and targets `EBSPROD_IAD2` **only** (§3).
- **Backups (independent failure domain):** **Oracle Database Autonomous Recovery Service protects the primary**, in whichever region is primary, with real-time redo transport (an extra-cost option that gets RPO "near the last sub-second" [13]) and retention lock for immutability [14]. Recovery Service replicates backups across availability domains *within* a region and can restore "to any availability domain, zone, or region" [13]; Oracle's stated cross-region pattern is "use Oracle Data Guard to replicate databases from primary to standby region and backup each region with local recovery service" [15]. **OCI automatic backups cannot be enabled on the Phoenix standby while the primary backs up to Recovery Service**: the ExaDB-D documentation permits automatic backups on a standby-role database in general [16], but the OCI release note states that customers can "enable or disable backup on the standby database only if the backup destination of the primary database is Object Storage" [17]. The Phoenix copy while Ashburn is primary is therefore a **customer-scheduled RMAN backup of the Active Data Guard standby to an Object Storage bucket** with a retention rule on the bucket *(unverified: engineering judgement; the standby-backup and bucket-retention mechanics were not verified against Oracle documentation in this revision)*. After any role change, automatic backups are disabled on the new standby [17] and Recovery Service must be enabled on the new primary (RB-02 §8). The alternative that Oracle's note permits — primary and standby both backing up to Object Storage with cross-region copy — keeps a Phoenix copy at all times but gives up real-time redo and retention lock; it is a business choice, recorded in `docs/05-cost-and-teardown.md` §4.
- **Oracle Flashback Database ON** on the primary and both standbys. Flashback is required for the Broker's `REINSTATE DATABASE` to succeed after a failover — "Flashback Database must have been enabled on the database prior to the failover" [9] — which is what makes failback fast (RB-03). It is *not* a prerequisite for snapshot-standby drills: those need only a Fast Recovery Area, since "it is not necessary for flashback database to be enabled" to convert a physical standby to a snapshot standby [12] (RB-04). Keep Flashback on regardless, since reinstate is the design's failback path.

> **HCC check.** Run `scripts/dataguard/check-hcc.sql` before sizing the standby. If any EBS or custom segment uses HCC, the PHX standby must be Exadata — a Base Database Service standby cannot query those segments.

### 4.2 Windows EBS application tier — Block Volumes

The volume model is stated exactly, because the adversarial review found the previous wording had activation both on and off the recovery path:

| Volume | Where it lives | Replicated? | Role at failover |
|---|---|---|---|
| **Boot volume** (Windows, Oracle Cloud Agent, MKS Toolkit, JRE, Forms client) | On every instance in every region and AD, built from the same Custom Image | **No** — a non-moving instance boots from its own boot volume; Full Stack DR attaches replicated volumes to the pre-provisioned standby instance rather than moving the instance [49] | Instance is started; nothing to activate |
| **EBS data volumes** (`fs1`, `fs2`, `fs_ne`, `$APPLCSF` log/out, `$APPL_TOP` per node) | Ashburn source volumes in one **Volume Group**; replica in Phoenix | **Yes** — **OCI Block Volume Volume Group Replication** (cross-region); all replicas in the group "are activated from the same coordinated synchronization point" [19] | **Activated** into a volume group (a clone of the replica [19]) and attached to the Phoenix instance — Full Stack DR's built-in "Volume Groups - Failover" then "Compute Instances - Attach Block Volumes" groups [38]. **This is on the critical path**; budget minutes for it in RTO |
| **Rebuild-from-scratch path** | **OCI Compute Custom Images** plus **Instance Configurations** | Image copied by export to Object Storage, copy of the object to the destination region, import there [20] | Tier-2 cold rebuild, and the drift-recovery path if a replica is corrupt |

Because EBS 12.2 on Windows does not support a shared application-tier file system (§4.4), each application node carries its own `fs1`/`fs2`/`fs_ne` on its own replicated data volumes; there is no separate "EBS clone" on the Phoenix nodes — the replicated copy *is* the Phoenix application tier, which is what makes the logical-host-name design (§5.1) work without AutoConfig. Individually replicated volumes are **not** mutually consistent — always use a volume group. Inbound/outbound interface landing directories are additionally staged in Object Storage (§4.4), because interface files are the most common source of Work Recovery Time (`docs/02-mtd-tiers.md` §6).

**Operational note.** Instance Configurations are fine for rebuilding compute, but **Full Stack DR does not support compute instances that are attached to an instance pool** [21] — if pool-managed scaling is in use for any Windows tier, that tier needs a Full Stack DR compute member design that avoids instance pools.

### 4.3 EBS 12.2 dual filesystem

EBS 12.2 online patching keeps two filesystems (`fs1`, `fs2`) — a run edition and a patch edition — plus `fs_ne` (non-editioned) [22]. **All three must be replicated.** A standby that has only the run edition will come up, but the next `adop` cycle will fail and you will have no patching capability in DR.

**Freeze rule: do not fail over mid-`adop` cycle.** If an online patching cycle is open when disaster strikes, the failover runbook has an `adop -abort` + `fs_clone` recovery branch, using the documented `adop -status`, `adop phase=abort`, and `adop phase=fs_clone` commands [22] (RB-02 §7). Track cycle state on the health dashboard.

### 4.4 Shared file systems — what they hold, and FSS vs Windows-native

**EBS 12.2 on Windows has no shared application-tier file system**: "Shared application tier file system functionality is not currently available on Windows" [47]. `fs1`/`fs2`/`fs_ne` therefore live on each node's own replicated data volumes (§4.2). The shared file systems in this plan (matrix row R5) hold only:

- **inbound and outbound interface landing directories** that every application node must see;
- **custom file drops** (bank files, EDI, scanned documents) written by integrations;
- the **concurrent output archive**, if one is kept on a share rather than per node.

These are write-heavy, so the replication interval bounds their loss: OCI File Storage replication runs at a minimum of 15 minutes, 60 by default [24][25]. That is why the primary recovery path for interface files is the Object Storage landing pattern in `docs/02-mtd-tiers.md` §6, not the share. Oracle's own EBS-on-OCI MAA paper did not rely on File Storage replication for this: "If you are using FSS, you can use the FSS file system synchronization, but be aware that it will only refresh the standby site once per hour. For our tests, we built scripts based on rsync" [54].

A genuine decision point remains, because **OCI File Storage supports the NFSv3 protocol** [23] and Windows NFS client support (the Windows Client for NFS, accessing exports anonymously via `AnonymousUid`/`AnonymousGid` mapping under AUTH_SYS) [27] is workable but has UID-mapping friction and no NFSv4 semantics. Whether that configuration is EBS-certified for Windows was not found in any source read for this revision *(unverified)*.

| Option | Use when | Cross-region mechanism | RPO |
|---|---|---|---|
| **A. OCI File Storage (FSS) — File System Replication**, mounted by the Windows *Client for NFS* [27] | Interface landing directories and file drops that Linux-side integrations also read | **FSS File System Replication** (cross-region, snapshot-delta based) [24] | Interval-driven — minimum 15 minutes, default 60 minutes if none is specified [24][25]. |
| **B. Windows File Server + Windows Server Storage Replica** | SMB-only consumers, ACL-sensitive shares | **Windows Server Storage Replica**, asynchronous, cross-region *(unverified: no Microsoft source read in this revision)* | seconds–minutes *(unverified)* |
| **C. Object Storage as the interchange** | Batch interface files, EDI drops, archive | **OCI Object Storage — Replication Policy** | minutes |

**Recommendation: C for all batch interchange (primary path), A for the shared directories above, B only where an application genuinely demands SMB semantics.** Option B is powerful but adds a Windows cluster you must patch, license, and DR-test independently — the highest-maintenance choice on this page.

> **FSS replication targets are read-only** while the replication resource exists [24]. Making one writable at failover means exporting it, which requires deleting the replication resource (or, if the source region is unreachable, deleting the replication target instead) [24][26]. **Once a target has been exported, re-establishing replication requires a full base copy**; a target that was never exported and had no snapshots created or deleted on it "can avoid a full base copy" and be reused directly [25]. This is a one-way door per failover event, once the target has been exported. Script it (`scripts/oci/fss-failover.sh`; `--lossless` runs one more replication cycle before deletion on a planned switchover) and account for the re-baseline window in the failback plan.

### 4.5 Visualization / BI tier

Point it at the **Active Data Guard standby in PHX for read-only reporting during normal operations.** This turns a cold asset into a working one and continuously proves the standby is healthy and queryable — the best DR test is the one that runs every day.

EBS caveat: Oracle's EBS 12.2 MAA white paper states that "the Oracle E-Business Suite supports a limited set of Oracle Active Data Guard functions" for reporting [29]. The documented reference for the restrictions is My Oracle Support Doc ID 1944539.1, *Using Active Data Guard Reporting with Oracle E-Business Suite Release 12.2 and an Oracle 11g or 12c Database* [28][29] — for a 19c database, the equivalent note is Doc ID 2608030.1, *Using Active Data Guard Reporting with Oracle E-Business Suite Release 12.2 and Oracle Database 19c* [30][31][32]. Do not simply repoint the standard EBS reporting stack at the standby and expect it to work; validate against the applicable note for your exact database and EBS patch level.

---

## 5. Network and naming — the single biggest RTO lever

### 5.1 Logical host names — Oracle's pattern, not identical computer names

**Design decision: physical computer names are unique per region and per availability domain (`IAD-EBSWEB01`, `PHX-EBSWEB01`, …); EBS is configured with logical host names (`ebsweb01`, `ebscm01`, …) that are the same in both regions and are resolved region-locally.**

This matters more than any other choice in this document. EBS bakes hostnames into context files, `FND_NODES`, WebLogic configs, and profile options. If the names EBS knows change at failover, Oracle's documented business-continuity sequence for a role transition is to purge `FND_NODES` and run AutoConfig on every tier: "Clean out the FND_NODES table by running the following command in SQL*Plus as the APPS user: `SQL> execute fnd_conc_clone.setup_clean;`", then run AutoConfig on the database tier, then "run AutoConfig on the middle tier for both RUN and PATCH file systems" [29].

```sql
EXEC FND_CONC_CLONE.SETUP_CLEAN;   -- purge FND_NODES
-- then AutoConfig on the DB tier, then AutoConfig on every app tier node
```

That path is **~3–5 hours** *(unverified: engineering judgement; no documentation found in this revision)*. Oracle's pattern for avoiding it is logical host names: "Each server is allocated a new, neutral name that is used to configure Oracle E-Business Suite so that the installation does not need to be re-configured when switching from one site to the other. These logical host names are different from the physical host names. They are not registered in the DNS – they are used only by Oracle E-Business Suite. Other tools continue to use the physical host names" [29] (My Oracle Support Doc ID 2246690.1 is the documented procedure [33]). With the names stable, app-tier recovery is *starting the services* — **~20–40 minutes** *(unverified: engineering judgement; no documentation found in this revision)*. The design therefore uses:

- **Unique physical names** per region and AD, each machine a distinct Active Directory computer account. Microsoft's guidance is to "use a unique name for every computer in your organization" and to avoid "using the same computer name for computers in different DNS domains" [48]; identically named machines cannot both hold a computer account in one domain.
- **Logical host names in the EBS context** (`s_hostname`, `s_webhost` and the related variables), resolved on each node to that region's physical hosts — a hosts file per Oracle's paper, or a region-scoped OCI Private DNS view, which is equivalent for EBS; "the same zone name can be used in many views, but zone names within a view must be unique" [51]. Active Directory DNS is untouched; domain-joined nodes resolve AD names through AD as before.
- **TNS aliases** that resolve region-locally, so context files never change; the SCAN names differ per region and Data Guard needs no shared names.
- Different VCN CIDRs (10.10/16 vs 10.20/16) — **required**, because both must be routable simultaneously for Data Guard.
- The **drill instances** get the same logical names in a drill-only resolution view, so a Level 2 drill starts EBS without AutoConfig (RB-04).

### 5.2 External entry point

**The EBS load balancer in each region is public-facing, behind OCI Web Application Firewall.** That is a design statement, not a detail: Traffic Management "is only available for public DNS, and isn't supported on private DNS" [34], and Health Checks monitors "allow you to continuously monitor the health of public-facing endpoints" [50]. An estate whose EBS entry point is private-only cannot use this mechanism; its alternative is a private-zone record swap performed by a Full Stack DR user-defined step, with no health-check-driven automation (`docs/03-replication-matrix.md` R8).

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
- **Plans:** Switchover, Failover, **Start Drill**, **Stop Drill** [44]. The drill plans are the tear-down-able DR environment. The published Start Drill order contains snapshot-standby conversion groups for Autonomous Database members but no documented group for an Oracle Database (ExaDB-D) member [38]; this plan converts the ExaDB-D standby through the OCI control plane — `oci db database convert-standby-database-type`, which "performs transition from standby database into a snapshot standby and vice versa" [53] — so that the Data Guard Group, the FSDR prechecks and the Broker agree on the role. While a drill is in progress, "if you attempt to execute a Switchover, Failover or Start Drill plan (or an associated precheck), you will get an error message indicating that this is a disallowed operation and that you must first execute a Stop Drill plan" [44] (RB-02 §0).
- **User-defined steps** run your EBS logic — stop/start services, `cmclean.sql`, AutoConfig where needed — via the **Oracle Cloud Agent Run Command plugin**, or by invoking an Oracle Function [39]. On Windows, a Run Command script executes in a batch shell by default; to run it under PowerShell, the script's first line must be `#ps1` [40]. Plain-text scripts uploaded directly are capped at 4 KB — larger scripts must be staged in Object Storage [40]. **The Run Command plugin must be enabled and healthy on every Windows instance, or plan execution fails at that step.** Verify it in prechecks, every time. The shipped PowerShell scripts start with `#ps1`, exceed 4 KB, and so are used through the **Run local script** step type (the file lives on the node) with **Stop on error** — "Stop on error – Indicates that DR plan execution should stop if step execution fails" [39] — running as the EBS service account with the EBS environment script and vault-supplied credentials.
- **The Data Guard member supports only one standby** of a Data Guard configuration — "Data Guard allows you to configure multiple standby database. However, Full Stack DR only supports one of these standby databases" [43]. That matches this design's single-Phoenix-standby topology and rules out adding a second FSDR-orchestrated standby without redesigning around it. **Automatic DR stays off** on the Data Guard member, for the reasons given in §3 [11].
- **Full Stack DR is a charged service**, billed monthly on the allocated OCPU/ECPU (or OIC message packs) of compute, database, OKE, and Integration members — whether running or stopped — with no additional charge for block, file, object storage, load balancer, or networking members [42]. Budget the always-on Windows and database members accordingly — and remember that the Exadata infrastructure itself keeps billing at zero OCPU: "With zero cores, you are billed only for the infrastructure until you scale up the system" [52].
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
46. *Oracle Data Guard Command-Line Interface Reference.* Oracle Data Guard Broker 19c, accessed
    2026-09-01. <https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/oracle-data-guard-broker-commands.html>
    — Supports: `DISABLE FAST_START FAILOVER` with the `FORCE` option "when the network between the
    primary and target standby databases is disconnected or when the database upon which the
    command is received does not have a connection with the primary database" (§3).
47. *Load Balancing.* Oracle E-Business Suite Concepts, Release 12.2, accessed 2026-09-01.
    <https://docs.oracle.com/cd/E26401_01/doc.122/e22949/T120505T120518.htm> — Supports: "Shared
    application tier file system functionality is not currently available on Windows" (§4.4, §4.2).
48. *Naming conventions in Active Directory for computers, domains, sites, and OUs.* Microsoft Learn,
    accessed 2026-09-01. <https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou>
    — Supports: "Use a unique name for every computer in your organization" and "Avoid using the
    same computer name for computers in different DNS domains" (§5.1).
49. *Add a Non-Moving Instance to a Disaster Recovery Protection Group.* OCI Full Stack DR
    documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-non-moving-instance.html>
    — Supports: non-moving instances stay in their region and receive attached volumes via a volume
    attachment reference ("Volume attachment reference is the peer compute instance used to get the
    attachment details") (§4.2).
50. *Health Checks.* OCI documentation, © 2026, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/Content/HealthChecks/Concepts/healthchecks.htm> — Supports:
    monitors "allow you to continuously monitor the health of public-facing endpoints" (§5.2).
51. *Private DNS.* OCI documentation, © 2026, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/Content/DNS/Tasks/privatedns.htm> — Supports: "The same
    zone name can be used in many views, but zone names within a view must be unique" (§5.1).
52. *Oracle Exadata Database Service on Dedicated Infrastructure Description.* Oracle, © 2026,
    accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/exadatacloud/doc/exa-service-desc.html>
    — Supports: "With zero cores, you are billed only for the infrastructure until you scale up the
    system" (cited from `docs/02-mtd-tiers.md` §4; listed here for completeness of the Exadata
    floor argument).
53. *convert-standby-database-type.* OCI CLI Command Reference 3.91.0, accessed 2026-09-01.
    <https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/db/database/convert-standby-database-type.html>
    — Supports: "Performs transition from standby database into a snapshot standby and vice versa"
    (§6).
54. *Maximum Availability Architecture: Oracle E-Business Suite on OCI.* Oracle, July 2025, Version
    1.0 (PDF), accessed 2026-09-01. <https://www.oracle.com/a/tech/docs/maaforebsonoci.pdf> —
    Supports: "If you are using FSS, you can use the FSS file system synchronization, but be aware
    that it will only refresh the standby site once per hour. For our tests, we built scripts based
    on rsync" (§4.4). HTTP 403 to automated fetch; retrieved with a browser user agent and read.

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
[46]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/oracle-data-guard-broker-commands.html "Data Guard Broker command reference 19c"
[47]: https://docs.oracle.com/cd/E26401_01/doc.122/e22949/T120505T120518.htm "EBS 12.2 Concepts — Load Balancing"
[48]: https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou "Microsoft — naming conventions for computers, domains, sites, and OUs"
[49]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-non-moving-instance.html "Full Stack DR — Add a Non-Moving Instance"
[50]: https://docs.oracle.com/en-us/iaas/Content/HealthChecks/Concepts/healthchecks.htm "OCI Health Checks"
[51]: https://docs.oracle.com/en-us/iaas/Content/DNS/Tasks/privatedns.htm "OCI Private DNS"
[52]: https://docs.oracle.com/en-us/iaas/exadatacloud/doc/exa-service-desc.html "ExaDB-D service description"
[53]: https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/db/database/convert-standby-database-type.html "OCI CLI — convert-standby-database-type"
[54]: https://www.oracle.com/a/tech/docs/maaforebsonoci.pdf "MAA: Oracle E-Business Suite on OCI (July 2025)"
