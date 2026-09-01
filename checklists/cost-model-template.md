# Cost Model Template

Fill in with your own rates. See `docs/05-cost-and-teardown.md` for the structure and for
why replica storage is the wrong thing to optimise.

Currency: ______  Pricing basis: ☐ list ☐ Universal Credits ☐ Annual Flex  Date: ______

## Fixed — accrues while DR exists

| Line item | Qty | Unit rate | Monthly | Notes |
|---|---|---|---|---|
| ExaDB-D Phoenix infrastructure | | | | by rack configuration; not reducible |
| Exadata storage / ASM capacity | | | | |
| ExaDB-D OCPU floor | | | | must be ≥ 1 to keep redo apply running |
| Block volume replica capacity | | | | boot + data, all nodes |
| FSS provisioned capacity (PHX) | | | | |
| Object Storage replica capacity | | | | |
| Autonomous Recovery Service — protected DB | | | | |
| Autonomous Recovery Service — cross-region copy | | | | |
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
| Cross-region egress — initial baselines | build | | |
| Cross-region egress — **failback baselines** | RB-03 | | **budget explicitly; every storage tier re-baselines** |
| Drill compute | per drill | | small; do not economise here |
| Emergency ExaDB-D scale-up | failover | | |

## Licensing — confirm in writing before build

| Item | Position | Confirmed by | Date |
|---|---|---|---|
| Standby database — BYOL vs license-included | | | |
| Oracle Active Data Guard on the standby | | | |
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
