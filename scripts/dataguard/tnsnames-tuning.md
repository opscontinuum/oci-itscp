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

**Use your measured RTT**, not 65 ms. Record it in `evidence/latency-baseline.md` —
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

`MaxAvailability` applies to the SYNC leg. The Phoenix member remains ASYNC, so a
Phoenix outage never stalls the primary.

## 5. Standby redo logs

Size **identical** to the online redo logs, with **one extra group per thread**:

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

Re-measure after every network change. Tuning that was correct at build time drifts
when bandwidth, routing, or workload changes.
