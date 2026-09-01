# Redo Transport Tuning — Ashburn to Phoenix

Applies to the ASYNC leg `EBSPROD_IAD` -> `EBSPROD_PHX`. The intra-region SYNC leg
to `EBSPROD_IAD2` needs none of this — at sub-millisecond latency the defaults are fine.

## 1. Size the TCP buffers from the bandwidth-delay product

```
BDP (bytes) = bandwidth (bits/s) / 8 * RTT (seconds)
```

Worked example at 1 Gbps and 65 ms RTT:

```
1,000,000,000 / 8 * 0.065 = 8,125,000 bytes  (~8.1 MB)
SEND_BUF_SIZE = RECV_BUF_SIZE = 3 x BDP     = ~24 MB
```

Oracle's own guidance is "the minimum recommended value for socket buffer sizes is 3*BDP,
especially for a high-latency, high-bandwidth network" [1]. **Use your measured RTT**, not
65 ms — Oracle states only that Ashburn–Phoenix latency "exceeds 50 ms RTT" [2]; it does not
publish an exact figure. Record your measurement in `evidence/latency-baseline.md` —
every RPO figure in `docs/02-mtd-tiers.md` derives from it.

## 2. tnsnames.ora — both ends

```
EBSPROD_PHX =
  (DESCRIPTION =
    (SDU = 65535)
    (SEND_BUF_SIZE = 25165824)
    (RECV_BUF_SIZE = 25165824)
    (ADDRESS = (PROTOCOL = TCP)(HOST = <phx-scan>)(PORT = 1521))
    (CONNECT_DATA = (SERVICE_NAME = EBSPROD_PHX))
  )
```

**On SDU:** 65535 is Oracle's MAA-recommended value specifically "for Synchronous Transport
Only" [1] — it is not the 19c maximum, which is 2097152 bytes [3]. It is used here as a
conservative, well-tested setting for the ASYNC leg too; if you tune further, test larger
values against your own network rather than assuming 65535 is a ceiling.

## 3. listener.ora — both ends

```
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (SDU = 65535)
      (ADDRESS = (PROTOCOL = TCP)(HOST = <scan>)(PORT = 1521))
    )
  )
```

## 4. Broker properties

```
DGMGRL> edit database 'EBSPROD_PHX' set property RedoCompression = 'ENABLE';
DGMGRL> edit database 'EBSPROD_PHX' set property LogXptMode = 'ASYNC';
DGMGRL> edit database 'EBSPROD_IAD2' set property LogXptMode = 'SYNC';
DGMGRL> edit database 'EBSPROD_IAD2' set property NetTimeout = '<n>';
DGMGRL> edit configuration set property FastStartFailoverThreshold = '<n>';
DGMGRL> edit configuration set protection mode as MaxAvailability;
```

**Licensing note:** `RedoCompression = ENABLE` requires the **Oracle Advanced Compression**
option — it is not included with Data Guard or Active Data Guard [4]. Confirm this is
licensed before enabling it (`docs/05-cost-and-teardown.md` §4).

`MaxAvailability` applies to the SYNC leg only. The Phoenix member remains ASYNC transport,
which "is done asynchronously with respect to transaction commitment, so primary database
performance is unaffected by the time required to transmit redo data and receive
acknowledgment from a standby database" [8] — a Phoenix outage never stalls the primary.

**On `NetTimeout`, set it explicitly — do not leave the default.** Under Maximum
Availability, "Maximum Availability will wait a maximum of NET_TIMEOUT seconds for an
acknowledgment from any of the standby databases, after which it will signal commit success
to the application and move to the next transaction" [1]. Oracle "recommends that the
NET_TIMEOUT attribute be specified whenever the synchronous redo transport mode is used, so
that the maximum duration of a redo source database stall caused by a redo transport fault
can be precisely controlled" [5]. An unset `NetTimeout` on `EBSPROD_IAD2` leaves that stall
duration undefined during an AD-2 network fault, and with it the RPO-0 claim in
`docs/01-architecture.md` §3. **What value to set is a measured, same-region decision, not
a published Oracle default** *(unverified: engineering judgement; measure against your own
network — see `docs/04-monitoring.md` §1–§2 for the alarm that watches the resulting
synchronized/unsynchronized state)*.

**On `FastStartFailoverThreshold`:** it bounds how long the observer waits, after losing
contact with the primary, before initiating an automatic failover. The default is 30
seconds; Oracle's recommended minimum is "6 to 15 seconds if the network is responsive and
reliable. For primary Oracle RAC instances, add maximum clusterware heartbeat timeout (CSS
miscount default for Linux is 30 seconds. For Exadata, you can use 2 seconds) to
FastStartFailoverThreshold" [1], and the guide's summary table separately gives "Oracle RAC
primary: Oracle RAC miscount + reconfiguration time + 30 seconds" [1].

**Before a planned switchover to Phoenix, this configuration must be downgraded first.**
Oracle's guidance for the analogous stretched-cluster case: "the protection level must be
dropped to Maximum Performance prior to a switchover (planned event) as the level must be
enforceable on the target in order to perform the transition" [1]:

```
DGMGRL> edit configuration set protection mode as MaxPerformance;
DGMGRL> edit database 'EBSPROD_IAD2' set property LogXptMode = 'ASYNC';
DGMGRL> disable fast_start failover;
```

Fast-start failover then stays **disabled** once Phoenix is primary — there is no
Phoenix-local SYNC standby for it to target — and `EBSPROD_IAD2` runs ASYNC. `RB-01` and
`RB-03` carry the full switchover and failback command sequence; this file only tunes the
properties. **State plainly wherever RPO 0 appears: RPO 0 exists only while Ashburn is
primary and `EBSPROD_IAD2` is synchronized. While Phoenix is primary, the database RPO is
the ASYNC transport lag measured in `docs/04-monitoring.md` §2.**

**Standby symmetry and the OCPU floor.** Redo apply performance depends on the standby
having comparable resources to the primary: "Oracle recommends that the primary and standby
database systems are symmetric, including equivalent I/O subsystems, memory, and CPU
resources… redo apply performance also benefits greatly from symmetric primary and standby
databases" [1]. `docs/05-cost-and-teardown.md` §2 holds the Phoenix standby at a low OCPU
floor between drills; whether that floor sustains redo apply against a captured
period-close redo rate has not been measured in this revision *(unverified: engineering
judgement; no documentation found in this revision)*. `docs/04-monitoring.md` §2 alarms on
apply lag rising while transport lag stays flat, the HA guide's stated signature of an apply
bottleneck.

## 5. Standby redo logs

Per Oracle's redo transport guidance [5], size standby redo logs **identical** to the online redo logs, with **one extra group per thread**:

```sql
-- for each thread, groups = (online groups + 1), same size
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 11 ('+RECO') SIZE <same-as-online>;
```

Undersized or missing standby redo logs silently disable real-time apply and force
archive-gap resolution — a common cause of "the lag looks fine but the RPO is not".

## 6. Parallelism

```sql
ALTER SYSTEM SET log_archive_max_processes = 8 SCOPE=BOTH;
```

## 7. Verify, do not assume

```sql
SELECT name, value, time_computed FROM v$dataguard_stats
 WHERE name IN ('transport lag','apply lag','apply finish time');

SELECT process, status, thread#, sequence#, block#
  FROM v$managed_standby WHERE process LIKE 'MRP%' OR process LIKE 'RFS%';
```

`V$DATAGUARD_STATS` documents `apply lag` as "a measure of the degree to which the data in
a target database lags behind the data in the originating database" and `transport lag` as
"a measure of the degree to which the transport of redo to the target database lags behind
the generation of redo on the originating database" [6]. These are the session-level source
of truth; the `oracle_oci_database` / `oracle_dataguard` `ApplyLag` and `TransportLag`
Monitoring metrics used in `docs/04-monitoring.md` are derived from the same underlying data
but require Database Management Diagnostics & Management to be enabled [7].

Re-measure after every network change. Tuning that was correct at build time drifts
when bandwidth, routing, or workload changes.

---

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *High Availability Overview and Best Practices.* Oracle Database 19c (F23691-56, July 14 2026), accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/haovw/high-availability-overview-and-best-practices.pdf> — Supports: "The minimum recommended value for socket buffer sizes is 3*BDP, especially for a high-latency, high-bandwidth network."; "Set SDU Size to 65535 for Synchronous Transport Only"; "Maximum Availability will wait a maximum of NET_TIMEOUT seconds for an acknowledgment..."; FastStartFailoverThreshold default (30 s) and recommended minimum ("6 to 15 seconds..."; "Oracle RAC primary: Oracle RAC miscount + reconfiguration time + 30 seconds"); "the protection level must be dropped to Maximum Performance prior to a switchover"; "Oracle recommends that the primary and standby database systems are symmetric... redo apply performance also benefits greatly from symmetric primary and standby databases" (§1, §2, §4).
2. *Set Up FMW Stretched Clusters.* Oracle Solutions (G49655-02, March 2026), accessed 2026-09-01.
   <https://docs.oracle.com/en/solutions/fmw-stretched-clusters/set-fmw-stretched-clusters1.html> — Supports: "the latency between these regions [Ashburn and Phoenix] exceeds 50 ms RTT" (§1).
3. *Parameters for the sqlnet.ora File.* Oracle Net Services Reference 19c, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/netrf/parameters-for-the-sqlnet.ora.html> — Supports: `DEFAULT_SDU_SIZE` value range is "512 to 2097152 bytes" (§2).
4. *Database Licensing Information User Manual 19c, Table 1-14.* Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html> — Supports: "Data Guard Redo Transport Compression" is listed under Oracle Advanced Compression (§4).
5. *Redo Transport Services.* Oracle Data Guard Concepts and Administration 19c, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-redo-transport-services.html> — Supports: "Each standby redo log file must be at least as large as the largest redo log file..."; "The standby redo log must have at least one more redo log group than the redo log at the redo source database, for each redo thread"; "If an acknowledgement is not received within NET_TIMEOUT seconds, the redo transport connection is terminated and an error is logged."; "Oracle recommends that the NET_TIMEOUT attribute be specified whenever the synchronous redo transport mode is used..." (§4, §5).
6. *V$DATAGUARD_STATS.* Oracle Database Reference 19c, §7.168, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-DATAGUARD_STATS.html> — Supports: `apply lag` and `transport lag` row definitions (§7).
7. *Oracle Cloud Database Metrics.* Database Management documentation, Oracle Cloud Infrastructure, no version shown, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/database-management/doc/oracle-cloud-database-metrics.html> — Supports: `ApplyLag`/`TransportLag` Monitoring metrics require Database Management Diagnostics & Management (§7).
8. *Oracle Data Guard Protection Modes.* Oracle Data Guard Concepts and Administration 19c, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-protection-modes.html> — Supports: "Redo data is also written to one or more standby databases, but this is done asynchronously with respect to transaction commitment, so primary database performance is unaffected by the time required to transmit redo data and receive acknowledgment from a standby database." (§4).

### Unverified statements

- The specific `NetTimeout` value to set on `EBSPROD_IAD2` is not published by Oracle as a
  same-region default; it must be measured against the actual network path (§4).
- Whether the OCPU floor recommended in `docs/05-cost-and-teardown.md` §2 sustains redo
  apply against a captured period-close redo rate has not been measured in this revision
  (§4).

[1]: https://docs.oracle.com/en/database/oracle/oracle-database/19/haovw/high-availability-overview-and-best-practices.pdf "High Availability Overview and Best Practices — Oracle Database 19c"
[2]: https://docs.oracle.com/en/solutions/fmw-stretched-clusters/set-fmw-stretched-clusters1.html "Set Up FMW Stretched Clusters — Oracle"
[3]: https://docs.oracle.com/en/database/oracle/oracle-database/19/netrf/parameters-for-the-sqlnet.ora.html "Parameters for the sqlnet.ora File — Oracle Net Services Reference 19c"
[4]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html "Database Licensing Information User Manual 19c — Oracle"
[5]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-redo-transport-services.html "Redo Transport Services — Oracle Data Guard Concepts and Administration 19c"
[6]: https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-DATAGUARD_STATS.html "V$DATAGUARD_STATS — Oracle Database Reference 19c"
[7]: https://docs.oracle.com/en-us/iaas/database-management/doc/oracle-cloud-database-metrics.html "Oracle Cloud Database Metrics — Database Management"
[8]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-protection-modes.html "Oracle Data Guard Protection Modes — Oracle Data Guard Concepts and Administration 19c"
