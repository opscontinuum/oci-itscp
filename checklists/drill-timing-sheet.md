# Drill Timing Sheet

Copy to `evidence/drill-YYYY-MM-DD/timing.md`. Record **wall-clock timestamps, not durations** —
durations are derived, and recording them directly is how errors creep in.

Drill date: __________  Level (1/2/3): ____  Lead: __________  Injected surprise: __________

## RTO segment

| Mark | Event | Timestamp (UTC) | Notes |
|---|---|---|---|
| T0 | Drill declared / incident simulated | | |
| T1 | Decision gate cleared (RB-02 §0) | | |
| T2 | FSDR plan execution started | | |
| T3 | Database role transition complete | | |
| T4 | Volume groups activated | | |
| T5 | FSS target unlocked | | |
| T6 | Windows instances RUNNING | | |
| T7 | Storage attached and mounted, fs1/fs2/fs_ne verified | | |
| T8 | `cmclean.sql` complete | | |
| T9 | Web/forms responding (first HTTP 200) | | |
| T10 | Concurrent Managers ACTUAL = TARGET | | |
| T11 | **First successful business transaction** | | ← **RTO ends here** |

**Measured RTO = T11 − T0 = __________**

## WRT segment

| Mark | Event | Timestamp (UTC) | Notes |
|---|---|---|---|
| W1 | In-flight request reconciliation started | | |
| W2 | Interface file replay complete | | |
| W3 | Outbound re-transmission ledger cleared | | |
| W4 | Reconciliation report pack complete | | |
| W5 | **Finance sign-off** | | ← **WRT ends here** |

**Measured WRT = W5 − T11 = __________**
**Measured MTD = W5 − T0 = __________**

## Comparison to target

| | Target (docs/02) | Measured | Variance | Within tier? |
|---|---|---|---|---|
| RPO | | | | |
| RTO | | | | |
| WRT | | | | |
| **MTD** | | | | |

## Defects raised

| # | Description | Severity | Owner | Due |
|---|---|---|---|---|
| 1 | | | | |

> **After the drill, update `docs/02-mtd-tiers.md` with these measured values.**
> The published tier table stays a design target until real measurements replace it.
