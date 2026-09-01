# DR Authority Matrix

Who may declare what, without waiting for whom. Agree this **before** an incident and have
it signed. During an outage nobody should be researching whether they are allowed to act.

| Action | Authority | Deputy | Consultation required | Without CAB? |
|---|---|---|---|---|
| Invoke RB-04 Level 1 (component test) | Infra on-call | any DBA | none | Yes |
| Invoke RB-04 Level 2 (Snapshot Standby drill) | DR Coordinator | Infra Manager | EBS functional lead | Yes, scheduled |
| Move posture WARM → HOT | Infra on-call | DR Coordinator | notify FinOps | Yes |
| Move posture HOT → WARM | DR Coordinator | Infra Manager | none | Yes |
| **Declare disaster / invoke RB-02 failover** | **DR Commander** | **Deputy DR Commander** | Business owner if reachable within 15 min | **Yes — do not wait for CAB** |
| Execute RB-01 planned switchover | DR Coordinator | — | CAB approval required | No |
| Proceed when data loss exceeds tier RPO | **Business owner + CFO delegate** | — | mandatory (RB-02 §7d) | No |
| Fail over during period close | **CFO or delegate** | — | mandatory | No |
| Start Concurrent Managers after failover | EBS functional lead | DBA on-call | after §7d clearance if RPO breached | Yes |
| Delete replication (decommission, RB-05 §5) | Infra Manager + Risk | — | written sign-off, both | No |
| Scale ExaDB-D below the OCPU floor | **Nobody** — refused by tooling | — | — | No |
| Initiate RB-03 failback | DR Coordinator | — | CAB + business approval | No |

## Standing decisions

Pre-agreed, so that no discussion is needed in the moment:

1. **Local (Ashburn) failover is automatic.** Oracle Data Guard Fast-Start Failover with the Observer handles AD-level loss without human involvement [1].
2. **Cross-region failover is never automatic.** It always requires a declared disaster. Full Stack DR's **Automatic DR** feature, which can trigger a plan on a Data Guard role change, is kept **disabled** for this reason (`docs/03-replication-matrix.md` §4) [2].
3. **Cross-region Fast-Start Failover is not configured, and that is a deliberate, not a safety, decision.** The Broker's observer fencing prevents split-brain regardless of distance [1] — the real reason is operational: a Phoenix database promoted by FSFO would have no running application tier to serve it until a human brings one up (`RB-02-failover.md` §0). A declared disaster with an explicit runbook is a better fit than an automatic promotion nobody was ready for.
4. **Estimated repair time greater than the remaining MTD budget means declare** — MTD minus time already elapsed on the gate minus the ~60-minute failover RTO, not a flat 2-hour figure (`RB-02-failover.md` §0). Do not wait for certainty; the decision gate exists to be used.
5. **If RPO is breached, Concurrent Managers stay down** until Finance clears them. Automated batch processing on incomplete data is far harder to unwind than a longer outage.

## Contact roster

| Role | Primary | Deputy | Reachable via | Verified |
|---|---|---|---|---|
| DR Commander | | | | |
| DBA on-call | | | | |
| Windows / infra on-call | | | | |
| Network on-call | | | | |
| EBS functional lead | | | | |
| Finance representative | | | | |
| Business owner | | | | |
| Oracle Support (CSI + severity-1 path) | | | | |

Signed: Business owner __________  CIO __________  Risk __________  Date __________

---

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *Switchover and Failover Operations.* Oracle Data Guard Broker 19c (E96245-04), Oracle, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html> — Supports: Fast-Start Failover, with an Observer on a separate host, transitions the primary role automatically without an administrator (Standing decisions).
2. *Configure Automatic DR Plan Execution.* OCI Full Stack DR documentation, © 2026, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/configure-automaticdr.html> — Supports: Full Stack DR can trigger a plan automatically when a Data Guard member changes role (Standing decisions).

[1]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/using-data-guard-broker-to-manage-switchovers-failovers.html "Switchover and Failover Operations — Oracle Data Guard Broker 19c"
[2]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/configure-automaticdr.html "Configure Automatic DR Plan Execution — Oracle"
