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
DGMGRL> edit configuration set protection mode as MaxAvailability;
```

**Licensing note:** `RedoCompression = ENABLE` requires the **Oracle Advanced Compression**
option — it is not included with Data Guard or Active Data Guard [4]. Confirm this is
licensed before enabling it (`docs/05-cost-and-teardown.md` §4).

`MaxAvailability` applies to the SYNC leg. The Phoenix member remains ASYNC, so a
Phoenix outage never stalls the primary.

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
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/haovw/high-availability-overview-and-best-practices.pdf> — Supports: "The minimum recommended value for socket buffer sizes is 3*BDP, especially for a high-latency, high-bandwidth network."; "Set SDU Size to 65535 for Synchronous Transport Only" (§1, §2).
2. *Set Up FMW Stretched Clusters.* Oracle Solutions (G49655-02, March 2026), accessed 2026-09-01.
   <https://docs.oracle.com/en/solutions/fmw-stretched-clusters/set-fmw-stretched-clusters1.html> — Supports: "the latency between these regions [Ashburn and Phoenix] exceeds 50 ms RTT" (§1).
3. *Parameters for the sqlnet.ora File.* Oracle Net Services Reference 19c, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/netrf/parameters-for-the-sqlnet.ora.html> — Supports: `DEFAULT_SDU_SIZE` value range is "512 to 2097152 bytes" (§2).
4. *Database Licensing Information User Manual 19c, Table 1-14.* Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html> — Supports: "Data Guard Redo Transport Compression" is listed under Oracle Advanced Compression (§4).
5. *Redo Transport Services.* Oracle Data Guard Concepts and Administration 19c, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-redo-transport-services.html> — Supports: "Each standby redo log file must be at least as large as the largest redo log file..."; "The standby redo log must have at least one more redo log group than the redo log at the redo source database, for each redo thread" (§5).
6. *V$DATAGUARD_STATS.* Oracle Database Reference 19c, §7.168, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-DATAGUARD_STATS.html> — Supports: `apply lag` and `transport lag` row definitions (§7).
7. *Oracle Cloud Database Metrics.* Database Management documentation, Oracle Cloud Infrastructure, no version shown, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/database-management/doc/oracle-cloud-database-metrics.html> — Supports: `ApplyLag`/`TransportLag` Monitoring metrics require Database Management Diagnostics & Management (§7).

[1]: https://docs.oracle.com/en/database/oracle/oracle-database/19/haovw/high-availability-overview-and-best-practices.pdf "High Availability Overview and Best Practices — Oracle Database 19c"
[2]: https://docs.oracle.com/en/solutions/fmw-stretched-clusters/set-fmw-stretched-clusters1.html "Set Up FMW Stretched Clusters — Oracle"
[3]: https://docs.oracle.com/en/database/oracle/oracle-database/19/netrf/parameters-for-the-sqlnet.ora.html "Parameters for the sqlnet.ora File — Oracle Net Services Reference 19c"
[4]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html "Database Licensing Information User Manual 19c — Oracle"
[5]: https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-redo-transport-services.html "Redo Transport Services — Oracle Data Guard Concepts and Administration 19c"
[6]: https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-DATAGUARD_STATS.html "V$DATAGUARD_STATS — Oracle Database Reference 19c"
[7]: https://docs.oracle.com/en-us/iaas/database-management/doc/oracle-cloud-database-metrics.html "Oracle Cloud Database Metrics — Database Management"
