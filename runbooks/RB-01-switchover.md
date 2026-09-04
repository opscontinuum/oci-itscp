# RB-01 — Planned Switchover: Ashburn → Phoenix

**Type:** Planned, orderly transition [1]; zero data loss for the database while the switchover completes — the storage tiers are bounded by replica age, not zero (§3). **Expected duration:** 45–90 min *(unverified: engineering judgement; no documentation found in this revision)*. **Approval:** Change Advisory Board.

> **RPO 0 is conditional.** It holds only while Ashburn is primary and `EBSPROD_IAD2` is synchronized under Maximum Availability. Once this runbook completes, Phoenix is primary under Maximum Performance with Ashburn as an ASYNC standby, and the database RPO becomes the ASYNC transport lag — see §2 and §6.
**Use when:** DR exercise with real production, planned Ashburn maintenance, or pre-emptive evacuation (e.g. forecast regional event).

> This is the **graceful** path — the database is healthy and reachable. If the primary is gone, use `RB-02-failover.md` instead. A switchover plan shuts the stack down in Ashburn and brings it up in Phoenix in an orderly way [1]; a failover does not attempt to shut the primary down [1], and the old primary must afterwards be reinstated with the Broker, which needs Flashback Database enabled beforehand [2].

---

## Sequence

```mermaid
sequenceDiagram
    autonumber
    participant OPS as DR Coordinator
    participant FSDR as Full Stack DR
    participant APP as Windows tiers (IAD)
    participant DG as Data Guard Broker
    participant PHX as Phoenix tiers
    participant DNS as Traffic Management

    OPS->>FSDR: Run prechecks (RB-01 §2)
    FSDR-->>OPS: All members healthy · lag within threshold
    OPS->>FSDR: Execute Switchover plan
    FSDR->>APP: Drain LB · stop Concurrent Managers
    FSDR->>APP: Stop Workflow Mailer · stop app services
    APP-->>FSDR: Quiesced
    FSDR->>DG: switchover to EBSPROD_PHX
    DG->>DG: Verify no gaps · transition roles
    DG-->>FSDR: EBSPROD_PHX is PRIMARY
    FSDR->>PHX: Activate volume groups · unlock FSS
    FSDR->>PHX: Scale Exadata OCPUs up
    FSDR->>PHX: Start instances · run cmclean.sql
    FSDR->>PHX: Start app services · Concurrent Managers
    PHX-->>FSDR: EBS responding
    FSDR->>DNS: Steer to Phoenix LB
    DNS-->>OPS: Cutover complete
    OPS->>OPS: Run validation pack (§5) → declare service
```

---

## 1. Pre-flight (T-24 h)

- [ ] Change approved; business notified of the outage window
- [ ] **No `adop` online-patching cycle open.** Verify: `adop -status` [3]. If a cycle is open, complete or abort it (`adop phase=abort`) [3] *before* the window — do not switch over mid-cycle.
- [ ] **Not in period close**, or Finance has explicitly signed off
- [ ] Data Guard lag below the plan threshold (60 s) and no gaps: `scripts/dataguard/dg-health.sh` (reads `V$DATAGUARD_STATS` transport lag and apply lag [4])
- [ ] All replication healthy: `scripts/oci/check-replication-health.sh`
- [ ] Oracle Cloud Agent **Run Command plugin** enabled and running on every PHX Windows instance — FSDR user-defined steps run only through Run Command (or Oracle Functions) [5], and the plugin must be enabled and running on the instance [6]. In our experience this is the #1 cause of plan-step failure *(unverified: engineering judgement; no documentation found in this revision)*
- [ ] Latest volume group replica timestamp within tolerance
- [ ] **No DR drill in progress.** While a DR Protection Group is in a `DrillInProgress` state, Switchover and Failover plans (and their prechecks) are refused until a Stop Drill plan runs [1]
- [ ] Rollback decision-maker identified and available for the whole window

## 2. Prechecks (T-1 h)

```bash
# 1. Downgrade protection ahead of the role transition. A synchronous, Maximum
#    Availability configuration cannot switch over to a target whose transport
#    mode does not support that protection level (see the trap below) — and once
#    Phoenix is primary there is no Ashburn-local synchronous standby to protect it
#    with anyway, so the configuration runs Maximum Performance / ASYNC from here on.
dgmgrl / "edit configuration set protection mode as MaxPerformance"
dgmgrl / "edit database 'EBSPROD_IAD2' set property LogXptMode='ASYNC'"
dgmgrl / "disable fast_start failover"

# 2. Data Guard configuration health
dgmgrl / "show configuration verbose"
dgmgrl / "validate database EBSPROD_PHX"     # must report "Ready for Switchover: Yes"

# OCI-side replication + member health
./scripts/oci/check-replication-health.sh          # regions and OCIDs come from terraform/dr-resources.env
```

The Broker is Oracle's recommended way to administer Data Guard for EBS [7]; the command-line scenarios for role transitions are documented in the Broker guide [8]. **The downgrade step is not optional.** Skip it and `VALIDATE DATABASE` can report the switchover blocked outright — the Broker's own worked example shows exactly this failure mode against a target whose `LogXptMode` is ASYNC while the configuration is still Maximum Availability: `Error: Switchover to this standby is not possible since there are no other standbys that can support the protection mode ... Ready for Switchover: No` [8]. Oracle's own MAA guidance for the equivalent Far Sync topology states the same requirement directly: "the protection level must be dropped to Maximum Performance prior to a switchover (planned event) as the level must be enforceable on the target in order to perform the transition" [31]. **Fast-start failover stays disabled after this switchover** — Phoenix becomes primary with no Ashburn-local synchronous standby it could name as an FSFO target *(unverified: engineering judgement; no documentation found in this revision)* — and `EBSPROD_IAD` runs onward as an ASYNC standby until failback (§6) re-enables Maximum Availability. With the downgrade done, the expected pass line is `Ready for Switchover: Yes` [8].

Run the FSDR **plan prechecks** from the console or CLI. Prechecks validate that the plan is compliant with the members and configuration of the protection groups — for example that the database and its peer are Data Guard peers with the correct roles, that a volume group replica exists in the standby region, and that the FSS target is unexported with a replication snapshot [9]. You can also tick **Enable prechecks** so they run before the switchover plan itself [10]. Every precheck must pass. Do not proceed on a warning you have not read and understood.

## 3. Execution

Execute the FSDR **Switchover** plan. It performs the sequence above: an orderly shutdown of the application stack in the primary region followed by bring-up in the standby region [1]. Monitor plan-step progress; a step configured **Stop on error** halts the plan on failure, while one configured **Continue on error** lets execution proceed regardless [5] — every user-defined EBS step in this plan must be Stop on error, because a step that fails silently mid-switchover (a stopped Run Command plugin, a failed `cmclean.sql`) is worse than a plan that stops and waits for a human.

**Manual fallback** if FSDR is unavailable — run in this order, do not reorder:

```bash
# 1. Quiesce the application tier (IAD) — Concurrent Managers FIRST
powershell -File scripts/windows/Stop-EBSAppTier.ps1 -Node ALL -Drain

# 2. Switch the database (protection mode already downgraded and FSFO disabled per §2)
dgmgrl sys/****@EBSPROD_IAD "switchover to EBSPROD_PHX"

# 3. Wait for the volume group replica to catch up to (approximately) the current
#    write rate before activating it — activation takes the replica's LAST synced
#    point, so activating early strands changes written after that point.
oci bv volume-group-replica get --volume-group-replica-id <replica-ocid> --region us-phoenix-1 \
  | jq -r '.data["time-last-synced"]'   # repeat until this is within one replication cycle of "now"

# 4. Bring up Phoenix storage, then compute, then EBS
#    All three take their OCIDs and region from terraform/dr-resources.env; all refuse
#    without --confirm and a --ticket.
#    --lossless on fss-failover.sh runs one final replication cycle before unlocking the target —
#    use it here because this is a planned switchover with a reachable source; RB-02 never uses it.
./scripts/oci/activate-volume-group.sh --vg-replica <replica-ocid> --region us-phoenix-1 --confirm --ticket "<change-ref>"
./scripts/oci/fss-failover.sh --replication <replication-ocid> --region us-phoenix-1 --lossless --confirm --ticket "<change-ref>"
./scripts/oci/scale-exadata-ocpu.sh --cluster EBSPROD_PHX --ocpu-per-node 16
powershell -File scripts/windows/Start-EBSAppTier.ps1 -Node ALL -RunCmClean

# 5. Steer traffic
./scripts/oci/steer-traffic.sh --target phoenix
```

What each fallback step does, and why the order holds:

- **Database switchover** can also be driven through the OCI control plane with `oci db database switch-over-data-guard` on a Data Guard Group [11]. Oracle's EBS control scripts on Windows are `adstpall.cmd` / `adstrtal.cmd` / `adcmctl.cmd` [12].
- **Volume groups:** activating the replica creates a *new* volume group by cloning the replica, from whatever point it was last synced; volumes are attachable only after activation [13]. All replicas in the group activate from the same coordinated synchronization point [14], read from the replica's own state [33] — that is why step 3 waits before step 4 activates: this is the difference between "zero data loss for the database" and the storage tiers' real, replica-age-bounded loss window.
- **FSS:** the target file system is read-only while the replication resource exists; to fail over, delete the replication (or the replication target if the source is gone) and export the target [15][16]. Deleting with `--delete-mode ONE_MORE_CYCLE` runs one final capture-and-apply cycle first — the OCI CLI documents this mode explicitly "for lossless failover" [32]; that is what `--lossless` selects.
- **Exadata OCPUs:** VM cluster OCPU scaling completes in minutes, without a cluster restart [17].
- **Traffic:** the Traffic Management **FAILOVER** policy serves answers in priority order and uses Health Checks to decide which answer is healthy [18]; `steer-traffic.sh` updates the policy with `oci dns steering-policy update` [19]. FSDR has no DNS member type, so this step is always ours [20].

## 4. Concurrent Manager handling

Always run `cmclean.sql` before starting Concurrent Managers in the new primary. Stale `FND_CONCURRENT_QUEUES` / ICM rows from the old region will otherwise prevent managers from starting, and the failure mode is confusing *(unverified: engineering judgement; no documentation found in this revision)*.

```sql
-- scripts/ebs/cmclean.sql   (obtain the current version from My Oracle Support Doc ID 134007.1)
-- Run as APPS, with all managers DOWN, then COMMIT.
```

**Applicability caveat.** `cmclean.sql` is a widely used practice, but its My Oracle Support note 134007.1 [21] is publicly described as valid for Applications releases 10.7 to 12.1.3 [22], and Oracle's EBS 12.2 business-continuity material does not contain a cmclean step [23]. Confirm applicability to your 12.2 release with Oracle Support before relying on it.

**Do not** run `FND_CONC_CLONE.SETUP_CLEAN` in a switchover — EBS is configured with **logical host names** that are resolved region-locally (`docs/01-architecture.md` §5.1), so `FND_NODES` never changes across a role transition and is already correct. Oracle's documented use of `setup_clean` is the post-role-transition clean-out of `FND_NODES` followed by AutoConfig on the database tier and then on every application tier node, for both run and patch file systems [23]; that is the cycle you would be forcing. Running it needlessly turns a one-hour switchover into a multi-hour one *(unverified: engineering judgement; no documentation found in this revision)*.

## 5. Validation pack

| # | Check | Pass criterion |
|---|---|---|
| V1 | `AppsLocalLogin.jsp` loads, test user logs in | HTTP 200, session established |
| V2 | Forms session opens (a real transaction form) | Form renders and commits a test record |
| V3 | Concurrent Managers | All target managers `ACTUAL = TARGET` |
| V4 | Submit "Active Users" concurrent request | Completes Normal |
| V5 | Workflow Mailer | Status running, test notification delivered |
| V6 | Inbound interface directory reachable and writable | Test file round-trips |
| V7 | Integration endpoints (SOA/ISG) | Health endpoint responds |
| V8 | Reverse Data Guard: `EBSPROD_IAD` now a standby, applying | Broker shows SUCCESS, `V$DATAGUARD_STATS` apply lag decreasing [4] |
| V9 | BI / visualization tier reconnected | Report renders |

Record results in `evidence/` with a timestamp. This is your audit artifact.

## 6. Post-switchover

- [ ] Confirm `EBSPROD_IAD` is receiving and applying redo as a standby [4]
- [ ] **Fast-start failover stays disabled; `EBSPROD_IAD` runs ASYNC.** This is not a defect to fix — Phoenix has no local synchronous standby to fail over to, so FSFO has nothing to target. The database RPO is now the ASYNC transport lag, not zero, until RB-03 restores Maximum Availability. Monitor transport lag as the RPO signal (`docs/04-monitoring.md` §2).
- [ ] **Re-point Autonomous Recovery Service to the new primary.** Automatic backup on a standby-role database is possible in principle [25], but is permitted only while the *primary's* backup destination is Object Storage — a primary cannot move its own backup destination to Recovery Service while the standby also has automatic backup enabled [24]. In practice this means only one region's database is protected by Recovery Service at a time. Enable the Recovery Service subscription (real-time redo, retention lock) on `EBSPROD_PHX` now that it is primary — the documented cross-region pattern is Data Guard between regions with each region's Recovery Service protecting whichever database is primary there [26]. `EBSPROD_IAD`, now standby, is **not** covered by Recovery Service while Phoenix is primary — its independent copy is the scheduled RMAN backup of the standby to Object Storage described in `docs/01-architecture.md` §4.1; confirm that schedule is running against `EBSPROD_IAD` before declaring the post-switchover state complete.
- [ ] Re-establish **reverse** replication for volume groups, FSS, and buckets (PHX→IAD). **This re-baselines** — see `docs/03-replication-matrix.md` §2. Start it immediately; it runs for hours.
  - Volume groups: enabling replication starts with an initial sync that "can take hours" depending on volume size and data written [27]; disabling deletes the replica, and re-enabling starts from scratch (Oracle states this in the resize context) [27].
  - FSS: a target that has been exported cannot be reused without a full base copy [28].
  - Object Storage: a new policy does **not** replicate objects that already exist in the source bucket [29] — bulk-copy the bucket contents first, then create the reverse policy.
- [ ] Scale IAD Exadata OCPUs down to the standby floor — scaling completes in minutes; the minimum is 2 OCPU per VM (8 ECPU per VM on X11M), and setting 0 shuts the VM cluster down [17]
- [ ] Stop IAD Windows instances (they are now the pilot light) — `oci compute instance action --action STOP` [30]
- [ ] Update the FSDR DRPG roles so Phoenix is primary
- [ ] Communicate new steady state; set a failback date (see RB-03)

## 7. Rollback

Before the database switchover completes, rollback is trivial — abort the plan and restart the IAD app tier. **After** the switchover, "rollback" *is* a second switchover back to Ashburn [1]: follow RB-01 in reverse. There is no fast undo. Make the go/no-go decision at step 3, not step 5.

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *Types of Disaster Recovery Plans.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/dr-plans-type.html> — Supports: switchover is a planned, orderly transition that shuts down the stack in the primary region then brings it up in the standby region; failover brings up the standby without attempting to shut down the primary (header, §3, §7).
2. *Switchover and Failover Operations.* Oracle Data Guard Broker 19c, E96245-04, accessed 2026-09-01. <https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html> — Supports: reinstate makes a failed primary a viable standby; "Flashback Database must have been enabled on the database prior to the failover" (header).
3. *Patching Procedures.* Oracle E-Business Suite Maintenance Guide, Release 12.2, no version shown, accessed 2026-09-01. <https://docs.oracle.com/cd/E26401_01/doc.122/e22954/T202991T531065.htm> — Supports: `adop -status` verifies no patching cycle is active; `adop phase=abort` aborts a cycle (§1).
4. *V$DATAGUARD_STATS.* Oracle Database Reference 19c, section 7.168, accessed 2026-09-01. <https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-DATAGUARD_STATS.html> — Supports: the view reports "transport lag" and "apply lag" rows (§1, §5 V8, §6).
5. *Add User-Defined Plan Groups and Steps.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-user-defined-plan-groups.html> — Supports: user-defined steps run only via Oracle Cloud Agent Run Command on member instances, or via Oracle Functions (§1).
6. *Running Commands on an Instance.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/runningcommands.htm> — Supports: the Run Command plugin must be enabled on the instance and plugins must be running (§1).
7. *E-Business Suite Release 12.2 Maximum Availability Architecture.* Oracle White Paper, January 2018, accessed 2026-09-01. <https://www.oracle.com/technetwork/database/availability/ebs-122-maa-whitepaper-4258573.pdf> — Supports: "Use Data Guard Broker to simplify Data Guard administration" (§2).
8. *Scenarios Using the DGMGRL Command-Line Interface.* Oracle Data Guard Broker 19c, E96245-04, accessed 2026-09-01. <https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/examples-using-data-guard-broker-DGMGRL-utility.html> — Supports: DGMGRL command-line scenarios for role transitions (§2).
9. *Prechecks Performed by Full Stack Disaster Recovery.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/prechecks-disaster-recovery.html> — Supports: prechecks validate protection groups, plans and executions; database Data Guard peers and roles; volume group replica present in standby region; target file system active and unexported with a replication snapshot (§2).
10. *Create Disaster Recovery Plan Executions.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/create-dr-plan-executions.html> — Supports: "Enable prechecks" runs prechecks before the switchover or failover plan (§2).
11. *oci db database.* OCI CLI Command Reference 3.91.0, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/db/database.html> — Supports: `switch-over-data-guard`, `failover-data-guard`, `reinstate-data-guard` subcommands for the Data Guard Group model (§3).
12. *Starting and Stopping Application Tier Services.* Oracle E-Business Suite Maintenance Guide, Release 12.2, no version shown, accessed 2026-09-01. <https://docs.oracle.com/cd/E26401_01/doc.122/e22954/T202991T530133.htm> — Supports: `adstrtal.cmd`, `adstpall.cmd`, `adcmctl.cmd` on Windows (§3).
13. *Activating a Volume Group Replica.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/Content/Block/Tasks/create-activate-replica-bv-volume-group.htm> — Supports: activating a replica creates a new volume group, the same as creating a clone; volumes usable only after activation (§3).
14. *Replicating Volume Groups.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/volumegroupreplication.htm> — Supports: all replicas are activated "from the same coordinated synchronization point" (§3).
15. *File System Replication.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/Content/File/Tasks/FSreplication.htm> — Supports: the target file system is read-only while replication exists; to fail over, export the target (§3).
16. *Deleting a Replication Target.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/Content/File/Tasks/delete-replication-target.htm> — Supports: delete the replication target to make the target file system exportable when the source is unavailable (§3).
17. *Manage VM Clusters.* Oracle Exadata Database Service on Dedicated Infrastructure, no version shown, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/exadatacloud/doc/manage-vm-clusters.html> — Supports: OCPU scaling operations complete in minutes; setting OCPUs to zero shuts down the VM cluster; minimum 2 OCPU per VM (8 ECPU on X11M) (§3, §6).
18. *Overview of Traffic Management.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/Content/TrafficManagement/Concepts/overview.htm> — Supports: FAILOVER policy priority order with Health Checks (§3).
19. *oci dns steering-policy update.* OCI CLI Command Reference 3.91.0, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/dns/steering-policy/update.html> — Supports: steering policy answers and rules are updated with this verb (§3).
20. *Add Members to a Disaster Recovery Protection Group.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-members-protection-group.html> — Supports: the member-type list contains no DNS or Traffic Management member (§3).
21. *Concurrent Processing - CMCLEAN.SQL - Non Destructive Script to Clean Concurrent Manager Tables* (My Oracle Support Doc ID 134007.1). Unverifiable by URL: login-gated (My Oracle Support). Title corroborated only by [22] (§4).
22. *Be Warned: cmclean.sql Is Dangerous!* Maris Elsins, Pythian blog, 2013-07-18, accessed 2026-09-01. <https://www.pythian.com/blog/be-warned-cmclean-sql-is-dangerous/> — Supports: corroborates the title of note 134007.1 only, and states the note "is valid for Applications versions 10.7 to 12.1.3" (§4).
23. *E-Business Suite Release 12.2 Maximum Availability Architecture.* Oracle White Paper, January 2018, section 8.2.5, accessed 2026-09-01. <https://www.oracle.com/technetwork/database/availability/ebs-122-maa-whitepaper-4258573.pdf> — Supports: steps 10–13: `fnd_conc_clone.setup_clean` cleans `FND_NODES`, then AutoConfig on the database node(s), then on the middle tier for run and patch file systems; the paper contains no cmclean step (§4).
24. *Backup and Restore from a Standby Database in a Data Guard Environment.* Oracle Cloud Infrastructure release note, August 24, 2023, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/releasenotes/changes/19e890da-7b15-4d55-a0b3-28058930a8f8/> — Supports: with Autonomous Recovery Service as the destination, "upon switchover, backup and restore will be disabled on the new standby database" (§6).
25. *Manage Database Backup and Recovery on Exadata Database Service on Dedicated Infrastructure.* Oracle Cloud Infrastructure Documentation, no version shown, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/exadatacloud/doc/ecs-managing-db-backup-and-recovery.html> — Supports: automatic backup can be enabled on a database with the standby role (§6).
26. *Implement Oracle Database Autonomous Recovery Service with Oracle Database@Azure.* Oracle solution playbook, G24007-01, January 2025, accessed 2026-09-01. <https://docs.oracle.com/en/solutions/implement-recovery-service-db-at-azure/index.html> — Supports: for cross-region, use Data Guard between regions and back up each region with a local Recovery Service (§6).
27. *Block Volume Replication.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/volumereplication.htm> — Supports: enabling replication includes an initial sync that "can take hours"; disabling replication deletes the replica and re-enabling "starts the replication process from scratch" (stated in the resize context) (§6).
28. *Creating a Replication.* Oracle Cloud Infrastructure Documentation (File Storage), © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/Content/File/Tasks/fsreplication-creating-a-replication.htm> — Supports: a never-exported former target can be reused and "avoid a full base copy"; an exported target cannot (§6).
29. *Object Storage Replication.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usingreplication.htm> — Supports: "Objects uploaded to a source bucket before policy creation aren't replicated" (§6).
30. *oci compute instance action.* OCI CLI Command Reference 3.91.0, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/compute/instance/action.html> — Supports: `--action STOP` / `START` (§6).
31. *High Availability Overview and Best Practices.* Oracle Database 19c, F23691-56, July 14 2026, accessed 2026-09-01. <https://docs.oracle.com/en/database/oracle/oracle-database/19/haovw/high-availability-overview-and-best-practices.pdf> — Supports: "the protection level must be dropped to Maximum Performance prior to a switchover (planned event) as the level must be enforceable on the target in order to perform the transition" (§2).
32. *oci fs replication delete.* OCI CLI Command Reference 3.91.0, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/fs/replication/delete.html> — Supports: `--delete-mode` accepts `ONE_MORE_CYCLE`, documented "Use for lossless failover" (§3).
33. *oci bv volume-group-replica get.* OCI CLI Command Reference 3.91.0, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/bv/volume-group-replica/get.html> — Supports: reads the replica's current state and last-synced timestamp before activation (§3).

### Unverified statements

- Header: expected duration 45–90 min — engineering estimate.
- §1: a stopped Run Command plugin is the #1 cause of plan-step failure — engineering judgement.
- §2: fast-start failover cannot re-target itself onto Phoenix because no Ashburn-local synchronous standby exists to name — engineering judgement; the consequence follows from the cited Broker documentation but is not itself stated in a fetched page.
- §4: stale `FND_CONCURRENT_QUEUES` / ICM rows block manager start after a role change — engineering judgement.
- §4: an unnecessary `SETUP_CLEAN` + AutoConfig cycle turns a one-hour switchover into a multi-hour one — engineering estimate.

[1]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/dr-plans-type.html "Types of Disaster Recovery Plans — Oracle"
[2]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html "Switchover and Failover Operations — Oracle Data Guard Broker 19c"
[3]: https://docs.oracle.com/cd/E26401_01/doc.122/e22954/T202991T531065.htm "Patching Procedures — Oracle E-Business Suite Maintenance Guide 12.2"
[4]: https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-DATAGUARD_STATS.html "V$DATAGUARD_STATS — Oracle Database Reference 19c"
[5]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-user-defined-plan-groups.html "Add User-Defined Plan Groups and Steps — Oracle"
[6]: https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/runningcommands.htm "Running Commands on an Instance — Oracle"
[7]: https://www.oracle.com/technetwork/database/availability/ebs-122-maa-whitepaper-4258573.pdf "E-Business Suite Release 12.2 Maximum Availability Architecture — Oracle"
[8]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/examples-using-data-guard-broker-DGMGRL-utility.html "Scenarios Using the DGMGRL Command-Line Interface — Oracle"
[9]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/prechecks-disaster-recovery.html "Prechecks Performed by Full Stack Disaster Recovery — Oracle"
[10]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/create-dr-plan-executions.html "Create Disaster Recovery Plan Executions — Oracle"
[11]: https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/db/database.html "oci db database — OCI CLI 3.91.0"
[12]: https://docs.oracle.com/cd/E26401_01/doc.122/e22954/T202991T530133.htm "Starting and Stopping Application Tier Services — Oracle E-Business Suite Maintenance Guide 12.2"
[13]: https://docs.oracle.com/en-us/iaas/Content/Block/Tasks/create-activate-replica-bv-volume-group.htm "Activating a Volume Group Replica — Oracle"
[14]: https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/volumegroupreplication.htm "Replicating Volume Groups — Oracle"
[15]: https://docs.oracle.com/en-us/iaas/Content/File/Tasks/FSreplication.htm "File System Replication — Oracle"
[16]: https://docs.oracle.com/en-us/iaas/Content/File/Tasks/delete-replication-target.htm "Deleting a Replication Target — Oracle"
[17]: https://docs.oracle.com/en-us/iaas/exadatacloud/doc/manage-vm-clusters.html "Manage VM Clusters — Oracle Exadata Database Service on Dedicated Infrastructure"
[18]: https://docs.oracle.com/en-us/iaas/Content/TrafficManagement/Concepts/overview.htm "Overview of Traffic Management — Oracle"
[19]: https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/dns/steering-policy/update.html "oci dns steering-policy update — OCI CLI 3.91.0"
[20]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/add-members-protection-group.html "Add Members to a Disaster Recovery Protection Group — Oracle"
[21]: #references "MOS Doc ID 134007.1 — unverifiable by URL (login-gated)"
[22]: https://www.pythian.com/blog/be-warned-cmclean-sql-is-dangerous/ "Be Warned: cmclean.sql Is Dangerous! — Pythian"
[23]: https://www.oracle.com/technetwork/database/availability/ebs-122-maa-whitepaper-4258573.pdf "E-Business Suite Release 12.2 Maximum Availability Architecture — Oracle, section 8.2.5"
[24]: https://docs.oracle.com/en-us/iaas/releasenotes/changes/19e890da-7b15-4d55-a0b3-28058930a8f8/ "Backup and Restore from a Standby Database in a Data Guard Environment — OCI release note"
[25]: https://docs.oracle.com/en-us/iaas/exadatacloud/doc/ecs-managing-db-backup-and-recovery.html "Manage Database Backup and Recovery — Oracle Exadata Database Service on Dedicated Infrastructure"
[26]: https://docs.oracle.com/en/solutions/implement-recovery-service-db-at-azure/index.html "Implement Oracle Database Autonomous Recovery Service with Oracle Database@Azure — Oracle"
[27]: https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/volumereplication.htm "Block Volume Replication — Oracle"
[28]: https://docs.oracle.com/en-us/iaas/Content/File/Tasks/fsreplication-creating-a-replication.htm "Creating a Replication — Oracle File Storage"
[29]: https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usingreplication.htm "Object Storage Replication — Oracle"
[30]: https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/compute/instance/action.html "oci compute instance action — OCI CLI 3.91.0"
[31]: https://docs.oracle.com/en/database/oracle/oracle-database/19/haovw/high-availability-overview-and-best-practices.pdf "High Availability Overview and Best Practices — Oracle Database 19c"
[32]: https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/fs/replication/delete.html "oci fs replication delete — OCI CLI 3.91.0"
[33]: https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/bv/volume-group-replica/get.html "oci bv volume-group-replica get — OCI CLI 3.91.0"
