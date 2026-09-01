# Pre-Failover Precheck

Run **monthly**, and again immediately before any planned switchover or drill.
OCI Full Stack Disaster Recovery plan prechecks validate member health; they cannot
validate your EBS logic [1]. This checklist covers that gap.

Record results in `evidence/precheck-YYYY-MM-DD.md`.

## A. Replication
- [ ] `./scripts/oci/check-replication-health.sh` exits 0
- [ ] Oracle Data Guard Broker configuration = SUCCESS, no warnings
- [ ] **Fast-start failover target and state known**: `EBSPROD_IAD2` is the current target, and whether FSFO is presently enabled or disabled matches what this runbook expects to find (`RB-01-switchover.md` §2, `RB-02-failover.md` §0) [4]
- [ ] **`NetTimeout` set** on the `EBSPROD_IAD2` (SYNC) leg, and `FastStartFailoverThreshold` set per the HA guide's formula — an unset `NetTimeout` turns an AD-2 network fault into an unbounded primary stall [5]
- [ ] **No DR drill in progress** (`DrillInProgress`) — Switchover, Failover, and Start Drill plans, and their prechecks, are refused while one is active [7]
- [ ] `VALIDATE DATABASE 'EBSPROD_PHX'` reports **Ready for Switchover: Yes** — if it instead reports the protection-mode error, the `RB-01-switchover.md` §2 downgrade sequence has not been run yet [6]
- [ ] Apply lag on the Phoenix leg within the tier threshold
- [ ] Apply lag on the Ashburn SYNC leg is zero
- [ ] Volume group replica last-sync within 30 minutes
- [ ] FSS File System Replication delta status healthy
- [ ] Object Storage Replication Policies all ACTIVE
- [ ] Autonomous Recovery Service protected database health = PROTECTED **on the current primary** — only one region's database is protected by Recovery Service at a time (`RB-01-switchover.md` §6)
- [ ] Oracle Flashback Database = YES on **all three** members (reinstate after failover)
- [ ] Fast Recovery Area below 75% on all members
- [ ] Fast Recovery Area has headroom for a guaranteed restore point on the Phoenix standby (Snapshot Standby drills need this; Flashback Database need not be enabled for it) [2]

## B. Orchestration
- [ ] FSDR Switchover plan prechecks pass, no warnings [1]
- [ ] FSDR Failover plan prechecks pass [1]
- [ ] Start Drill / Stop Drill plans present and passing [1]
- [ ] Oracle Cloud Agent **Run Command plugin** RUNNING on every Phoenix Windows instance
- [ ] FSDR plan execution log bucket writable
- [ ] DRPG membership matches `docs/03-replication-matrix.md` §4 — no resource added since the last review is unprotected

## C. EBS readiness
- [ ] `adop -status` clean — **no open online patching cycle**
- [ ] `fs1`, `fs2` **and** `fs_ne` all present and replicating
- [ ] `cmclean.sql` present at `scripts/ebs/cmclean.sql` and current — its My Oracle Support note predates 12.2; confirm applicability with Oracle Support (`scripts/ebs/README.md`) [3]
- [ ] `FND_NODES` contents match expected hostnames in both regions
- [ ] EBS patch level identical across regions
- [ ] Not in period close, or Finance has signed off

## D. Network and access
- [ ] DRG Remote Peering Connection up; routing verified **both** directions
- [ ] Measured RTT within 20% of `evidence/latency-baseline.md`
- [ ] Region-local resolution correctly maps the EBS logical hostnames from **both** regions
- [ ] OCI Traffic Management health checks green
- [ ] OCI Vault keys present and enabled in Phoenix
- [ ] Break-glass credentials tested within the last 90 days

## E. People
- [ ] DR Commander and deputy identified and reachable
- [ ] DBA, Windows, network, EBS functional, and Finance contacts current
- [ ] Escalation tree tested within the last 90 days
- [ ] Runbooks accessible **from outside Ashburn** — verify they are not hosted only in the region you are recovering from

> The last item is the one people fail. If the runbook lives on a wiki hosted in the
> primary region, you do not have a runbook.

---

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *Prechecks Performed by Full Stack Disaster Recovery.* OCI Full Stack DR documentation, © 2026, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/prechecks-disaster-recovery.html> — Supports: FSDR plan prechecks validate DR Protection Group, plan, and execution configuration, not application-level readiness (intro, §B).
2. *Managing Physical and Snapshot Standby Databases.* Oracle Data Guard Concepts and Administration 19c, Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/managing-oracle-data-guard-physical-standby-databases.html> — Supports: "Ensure that a fast recovery area has been configured. It is not necessary for flashback database to be enabled." for converting to a Snapshot Standby (§A).
3. *Be Warned: cmclean.sql Is Dangerous!* Maris Elsins, Pythian blog, 2013-07-18, accessed 2026-09-01.
   <https://www.pythian.com/blog/be-warned-cmclean-sql-is-dangerous/> — Supports: corroborates the title of My Oracle Support Doc ID 134007.1 and states the note "is valid for Applications versions 10.7 to 12.1.3" (§C).
4. *Switchover and Failover Operations.* Oracle Data Guard Broker 19c, E96245-04, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html> — Supports: fast-start failover behaviour is target- and state-dependent — a switchover or manual failover can only target the pre-specified FSFO target while FSFO is enabled (§A).
5. *Redo Transport Services.* Oracle Data Guard Concepts and Administration 19c, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-redo-transport-services.html> — Supports: "Oracle recommends that the NET_TIMEOUT attribute be specified whenever the synchronous redo transport mode is used" (§A).
6. *Scenarios Using the DGMGRL Command-Line Interface.* Oracle Data Guard Broker 19c, E96245-04, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/examples-using-data-guard-broker-DGMGRL-utility.html> — Supports: worked example output "Ready for Switchover: Yes" / "Ready for Switchover: No" with the protection-mode error when the target's LogXptMode does not match (§A).
7. *Types of Disaster Recovery Plans.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/dr-plans-type.html> — Supports: while a DR Protection Group is in a DrillInProgress state, Switchover, Failover, and Start Drill plans (and their prechecks) are refused until a Stop Drill plan runs (§A).

[1]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/prechecks-disaster-recovery.html "Prechecks Performed by Full Stack Disaster Recovery — Oracle"
[2]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/managing-oracle-data-guard-physical-standby-databases.html "Managing Physical and Snapshot Standby Databases — Oracle"
[3]: https://www.pythian.com/blog/be-warned-cmclean-sql-is-dangerous/ "Be Warned: cmclean.sql Is Dangerous! — Pythian"
[4]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html "Switchover and Failover Operations — Oracle Data Guard Broker 19c"
[5]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-redo-transport-services.html "Redo Transport Services — Oracle Data Guard Concepts and Administration 19c"
[6]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/examples-using-data-guard-broker-DGMGRL-utility.html "Scenarios Using the DGMGRL Command-Line Interface — Oracle Data Guard Broker 19c"
[7]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/dr-plans-type.html "Types of Disaster Recovery Plans — Oracle"
