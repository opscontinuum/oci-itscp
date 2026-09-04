# evidence/

Artifacts that turn this plan from a document into a program: proof that the DR environment was
healthy, was tested, and performed as claimed.

> **In this example repository** this directory is a structural placeholder. Anything added
> here is clearly-labeled illustrative sample data for the hypothetical corporation
> described in the root README. It is not real operational output.

## What lands here in a real deployment

| Artifact | Produced by | Cadence |
|---|---|---|
| `posture-log.md` | `scripts/oci/set-dr-posture.sh` | every posture change |
| `storage-failover-log.md` | the guarded storage-failover scripts | every one-way-door action |
| `precheck-YYYY-MM-DD.md` | `checklists/pre-failover-precheck.md` | monthly, and pre-drill |
| `drill-YYYY-MM-DD/timing.md` | `checklists/drill-timing-sheet.md` | every drill |
| `drill-YYYY-MM-DD/` (logs, screenshots, defects, sign-off), including the FSDR plan execution log [1] | RB-04 §5 | every drill |
| `rpo-attestation-YYYY-MM.md` | `scripts/oci/generate-rpo-attestation.sh` | monthly |
| `drift-YYYY-MM-DD.md` | `scripts/oci/detect-drift.sh` | weekly |
| `latency-baseline.md` | measured at build, re-measured on network change | at build, then on change |
| `inflight-requests-*.txt` | `Stop-EBSAppTier.ps1` | every controlled shutdown |
| `lag-snapshot-<UTC>.md` | `scripts/dataguard/capture-lag-snapshot.sh` | at the moment of loss (RB-02 §1) |
| `replication-state-<UTC>.md` | `scripts/oci/capture-replication-state.sh` | at the moment of loss (RB-02 §1) |
| `ocpu-scale-log.md` | `scripts/oci/scale-exadata-ocpu.sh` | every OCPU change |
| `traffic-steering-log.md` | `scripts/oci/steer-traffic.sh` | every steering change |
| `drift-<host>.md` (in-guest) | `scripts/windows/Compare-NodeDrift.ps1 -Mode Compare` | weekly, and before failback (RB-03 §4) |
| `decommission-log.md` | `scripts/oci/decommission-dr.sh` | decommission only (RB-05 §5) |

## Sensitivity — decide before your first drill

This becomes the most sensitive directory in the repository. It accumulates real hostnames,
real replication lag figures, real incident narratives, and captured concurrent request
lists. It is also the first thing an auditor will ask for.

`.gitignore` currently excludes `evidence/*.csv` and `evidence/*.json`. **Markdown is not
excluded**, and most of the templates above produce Markdown. Before committing any real
output, choose one:

**Option A — ignore the contents, keep the structure**
```gitignore
evidence/*
!evidence/.gitkeep
!evidence/README.md
```

**Option B — separate private repository**
Keep evidence in its own private repo and reference it from here. Preferable when the
plan itself is shared more widely than the operational results.

Option B is the better fit if you are adapting this public example, because it lets the
plan stay reviewable without dragging operational detail along with it.

## Retention

Drill evidence and RPO attestations typically fall under the same records-retention
schedule as other SOX-relevant IT control evidence. Confirm the period with your risk
function, and note that `runbooks/RB-05-replication-lifecycle.md` §5 requires archiving
this directory **before** any decommission — the step most often skipped.

## References

This document is a synthesis: every statement about product behavior or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *Preparing Log Location for Operation Logs.* Oracle Cloud Infrastructure Documentation, © 2026, accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/object-storage-for-logs.html> — Supports: each DR Protection Group writes its plan execution logs to a dedicated Object Storage bucket ("What lands here in a real deployment").

[1]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/object-storage-for-logs.html "Preparing Log Location for Operation Logs — Oracle"
