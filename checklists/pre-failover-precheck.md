# Pre-Failover Precheck

Run **monthly**, and again immediately before any planned switchover or drill.
OCI Full Stack Disaster Recovery plan prechecks validate member health; they cannot
validate your EBS logic. This checklist covers that gap.

Record results in `evidence/precheck-YYYY-MM-DD.md`.

## A. Replication
- [ ] `./scripts/oci/check-replication-health.sh` exits 0
- [ ] Oracle Data Guard Broker configuration = SUCCESS, no warnings
- [ ] `VALIDATE DATABASE 'EBSPROD_PHX'` reports **Ready for Switchover: Yes**
- [ ] Apply lag on the Phoenix leg within the tier threshold
- [ ] Apply lag on the Ashburn SYNC leg is zero
- [ ] Volume group replica last-sync within 30 minutes
- [ ] FSS File System Replication delta status healthy
- [ ] Object Storage Replication Policies all ACTIVE
- [ ] Autonomous Recovery Service protected database health = PROTECTED
- [ ] Oracle Flashback Database = YES on **all three** members
- [ ] Fast Recovery Area below 75% on all members

## B. Orchestration
- [ ] FSDR Switchover plan prechecks pass, no warnings
- [ ] FSDR Failover plan prechecks pass
- [ ] Start Drill / Stop Drill plans present and passing
- [ ] Oracle Cloud Agent **Run Command plugin** RUNNING on every Phoenix Windows instance
- [ ] FSDR plan execution log bucket writable
- [ ] DRPG membership matches `docs/03-replication-matrix.md` §4 — no resource added since the last review is unprotected

## C. EBS readiness
- [ ] `adop -status` clean — **no open online patching cycle**
- [ ] `fs1`, `fs2` **and** `fs_ne` all present and replicating
- [ ] `cmclean.sql` present at `scripts/ebs/cmclean.sql` and current
- [ ] `FND_NODES` contents match expected hostnames in both regions
- [ ] EBS patch level identical across regions
- [ ] Not in period close, or Finance has signed off

## D. Network and access
- [ ] DRG Remote Peering Connection up; routing verified **both** directions
- [ ] Measured RTT within 20% of `evidence/latency-baseline.md`
- [ ] Private DNS resolves the identical hostnames correctly from **both** regions
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
