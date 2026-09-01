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

1. **Local (Ashburn) failover is automatic.** Oracle Data Guard Fast-Start Failover with the Observer handles AD-level loss without human involvement.
2. **Cross-region failover is never automatic.** It always requires a declared disaster.
3. **Estimated repair time greater than the Tier-0 MTD of 2 hours means declare.** Do not wait for certainty; the decision gate in RB-02 §0 exists to be used.
4. **If RPO is breached, Concurrent Managers stay down** until Finance clears them. Automated batch processing on incomplete data is far harder to unwind than a longer outage.

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
