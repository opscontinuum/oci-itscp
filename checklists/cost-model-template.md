# Cost Model Template

Fill in with your own rates. See `docs/05-cost-and-teardown.md` for the structure and for
why replica storage is the wrong thing to optimise.

Currency: ______  Pricing basis: ☐ list ☐ Universal Credits ☐ Annual Flex  Date: ______

## Fixed — accrues while DR exists

| Line item | Qty | Unit rate | Monthly | Notes |
|---|---|---|---|---|
| ExaDB-D Phoenix infrastructure | | | | by rack configuration; not reducible |
| Exadata storage / ASM capacity | | | | |
| ExaDB-D OCPU floor | | | | must be ≥ 2 OCPU per VM (8 ECPU per VM on X11M); 0 OCPU shuts the VM cluster down [1] |
| Block volume replica capacity | | | | boot + data, all nodes |
| FSS provisioned capacity (PHX) | | | | |
| Object Storage replica capacity | | | | |
| Autonomous Recovery Service — protected DB (whichever region is primary) | | | | **one active subscription at a time**, not one per region — automatic backup on a standby-role database is possible in principle, but only while the primary's own backup destination is Object Storage, so primary and standby cannot both be Recovery-Service-protected simultaneously [2][3]; there is no cross-region backup-copy feature |
| Object Storage bucket — RMAN backup of the standby | | | | the standby's independent copy while it is ineligible for Recovery Service; customer-scheduled RMAN job, not an OCI-managed feature — bucket storage plus the bucket's retention rule |
| Autonomous Recovery Service — real-time redo transport | | | | extra-cost option, on the currently active subscription [2] |
| Full Stack Disaster Recovery — allocated OCPU/ECPU | | | | compute + database members, **both regions**, whether running or stopped [4] |
| OCI Vault / DNS / Health Checks | | | | small, but list them |
| **Fixed subtotal** | | | | |

## Elastic — reclaimed in WARM posture

| Line item | Qty | Unit rate | Monthly (HOT) | Monthly (WARM) | Saving |
|---|---|---|---|---|---|
| Windows compute OCPU + memory | | | | 0 | |
| ExaDB-D OCPUs above floor | | | | 0 | |
| **Elastic subtotal** | | | | | |

## Event-driven

| Line item | Trigger | Estimated cost | Notes |
|---|---|---|---|
| Cross-region egress — initial baselines | build | | first 10 TB/month outbound is free on the published price list, priced above that [5] |
| Cross-region egress — **failback baselines** | RB-03 | | **budget explicitly; every storage tier re-baselines** |
| Drill compute | per drill | | small; do not economise here |
| Emergency ExaDB-D scale-up | failover | | |

## Licensing — confirm in writing before build

| Item | Position | Confirmed by | Date |
|---|---|---|---|
| Standby database — BYOL vs license-included | | | |
| Oracle Active Data Guard on the standby | | | required for real-time query, Far Sync, automatic block repair [6] |
| Oracle Advanced Compression option | | | required if Data Guard redo transport compression is enabled [6] |
| Windows Server licensing in OCI | | | |
| EBS entitlement for a DR instance | | | |
| EBS entitlement for **Snapshot Standby opened read-write quarterly** (RB-04) | | | |

> The last row is the one most often missed. Get it confirmed by your Oracle account team
> before the first drill, not after the first audit.

## Summary

| Posture | Monthly cost | % of production | Tier met |
|---|---|---|---|
| Production (Ashburn) | | 100% | — |
| DR — HOT | | | Tier 0 |
| DR — WARM | | | Tier 1, elevates in minutes |
| DR — "delete replication to save money" | | | **None. This is not DR.** |

---

## References

This document is a synthesis: every statement about product behavior or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *Manage VM Clusters.* Exadata Database Service on Dedicated Infrastructure documentation, no version shown, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/exadatacloud/doc/manage-vm-clusters.html> — Supports: "setting the number of OCPUs (ECPUs for X11M) to zero will shut down the VM Cluster and eliminate any billing for that VM Cluster" (Fixed).
2. *Recovery Service Technical Architecture.* Oracle Database Autonomous Recovery Service documentation, no version shown, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/recovery-service/doc/recovery-service-architecture.html> — Supports: real-time redo transport is an extra-cost option; backup replication is intra-region, not cross-region (Fixed).
3. *Implement Oracle Database Autonomous Recovery Service with Oracle Database@Azure.* Oracle Solutions playbook (G24007-01, January 2025), accessed 2026-09-01.
   <https://docs.oracle.com/en/solutions/implement-recovery-service-db-at-azure/index.html> — Supports: the documented cross-region pattern is Data Guard between regions plus a local Recovery Service in each region (Fixed).
4. *Full Stack DR Billing Details.* OCI Full Stack DR documentation, © 2026, accessed 2026-09-01.
   <https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/billing-details.html> — Supports: FSDR bills monthly on allocated OCPU/ECPU of compute and database members in both regions, whether running or stopped (Fixed).
5. *Cloud Price List.* Oracle, © 2026, accessed 2026-09-01.
   <https://www.oracle.com/cloud/networking/pricing/> — Supports: first 10 TB/month of outbound data transfer is free, priced above that (Event-driven).
6. *Database Licensing Information User Manual 19c.* Oracle, no version date shown, accessed 2026-09-01.
   <https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html> — Supports: Active Data Guard licenses real-time query, Far Sync, and automatic block repair; RedoCompression requires the Advanced Compression option (Licensing).

[1]: https://docs.oracle.com/en-us/iaas/exadatacloud/doc/manage-vm-clusters.html "Manage VM Clusters — Oracle"
[2]: https://docs.oracle.com/en-us/iaas/recovery-service/doc/recovery-service-architecture.html "Recovery Service Technical Architecture — Oracle"
[3]: https://docs.oracle.com/en/solutions/implement-recovery-service-db-at-azure/index.html "Implement Oracle Database Autonomous Recovery Service with Oracle Database@Azure — Oracle"
[4]: https://docs.oracle.com/en-us/iaas/disaster-recovery/doc/billing-details.html "Full Stack DR Billing Details — Oracle"
[5]: https://www.oracle.com/cloud/networking/pricing/ "Cloud Price List — Oracle"
[6]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html "Database Licensing Information User Manual 19c — Oracle"
