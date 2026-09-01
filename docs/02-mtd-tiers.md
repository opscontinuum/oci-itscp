# 02 — Maximum Tolerable Downtime (MTD) Tiers

## 1. Getting the vocabulary right

Most DR plans quote RTO and stop. That under-states EBS recovery badly, because an ERP is not "recovered" when the database opens — it is recovered when Finance trusts the numbers.

![MTD timeline: RPO before the incident, RTO then WRT after it, MTD spanning both](diagrams/mtd-timeline.svg)

| Term | Definition | Who owns it |
|---|---|---|
| **RPO** | Recovery Point Objective — how much committed data you accept losing | Infrastructure / DBA |
| **RTO** | Recovery Time Objective — incident to *technically available* | Infrastructure / DBA |
| **WRT** | Work Recovery Time — technically available to *business-usable*: concurrent request re-submission, interface replay, reconciliation, period-close validation | EBS functional + Finance |
| **MTD** | **RTO + WRT** — the number the business actually feels, and the only one to put in front of an executive | Business owner |

**Everything below is expressed as MTD.** WRT is called out separately because for EBS it is frequently *larger* than RTO, and it is the part no infrastructure investment can shrink — it shrinks only through interface design and rehearsal.

---

## 2. The four tiers

![Four DR tiers plotted by MTD on a log scale against relative run cost](diagrams/tier-ladder.svg)

| | **Tier 0 — Platinum** | **Tier 1 — Gold** | **Tier 2 — Silver** | **Tier 3 — Bronze** |
|---|---|---|---|---|
| **Posture** | Hot standby | Warm / pilot light | Cold, pre-staged | Backup & restore |
| **RPO** | **0** intra-region<br>**< 30 s** cross-region | **≤ 5 min** | **≤ 1 hr** | **≤ 24 hr** |
| **RTO** | ≤ 15 min local<br>≤ 60 min cross-region | ≤ 4 hr | ≤ 12 hr | ≤ 72 hr |
| **WRT** | ~30 min | ~2 hr | ~4 hr | ~8 hr |
| **MTD** | **≤ 2 hr** | **≤ 6 hr** | **≤ 24 hr** | **≤ 5 days** |
| **Database** | **Oracle Active Data Guard** — SYNC intra-region + ASYNC to PHX, real-time apply; **FSFO + Observer** on the local leg | **Oracle Active Data Guard**, ASYNC, real-time apply | **Oracle Data Guard** managed recovery, ExaDB-D VM Cluster at OCPU floor | **Oracle Database Autonomous Recovery Service** — cross-region backup copy, `RMAN RESTORE` |
| **Windows app tier** | Running; EBS services stopped, drained from **OCI Flexible Load Balancer** | Instances exist, **STOPPED** via **OCI Resource Scheduler** (no OCPU billing) | **OCI Compute Custom Images** + volume group replicas only | Rebuild from **Custom Image** + backup |
| **Block storage** | **OCI Block Volume — Volume Group Replication**, continuous | **Volume Group Replication**, continuous | **Volume Group Replication** | **OCI Block Volume Backup Policy** — cross-region backup copy |
| **File storage** | **OCI File Storage — File System Replication**, shortest supported interval | **FSS File System Replication** | **FSS File System Replication**, long interval | FSS snapshot exported to Object Storage |
| **Object storage** | **OCI Object Storage — Replication Policy** | **Object Storage Replication Policy** | **Object Storage Replication Policy** | Lifecycle-managed cross-region copy |
| **Failover trigger** | **Full Stack DR — Failover plan**, pre-approved | **Full Stack DR** plan + change approval | **Full Stack DR** plan + manual staging | Manual rebuild |
| **Relative run cost** | ~90–100% of prod | ~45–60% | ~20–30% | ~5–10% |

> Cost percentages are **shape-of-the-answer, not a quote.** They exclude the Exadata infrastructure floor discussed in §4. Model your own in `docs/05-cost-and-teardown.md`.

---

## 3. Which EBS component lands in which tier

This is the part to negotiate with the business. A defensible split:

| Scope | Tier | Rationale |
|---|---|---|
| Core financials — GL, AP, AR, FA; Order Management, Inventory transactions; the EBS database itself | **0** | Revenue-recognition and cash-application paths. Data loss is not recoverable by re-keying. |
| Full production app tier — Concurrent Managers, Workflow, Workflow Mailer, iProcurement, self-service HR, integration endpoints (SOA/ISG) | **1** | Business can absorb a few hours; most work re-queues rather than being lost. |
| Visualization / BI / reporting tier, ad-hoc analytics, data extracts, non-critical inbound integrations | **2** | Reporting can wait a day. **Note:** if the BI tier reads the ADG standby, it is effectively *available first* — a pleasant inversion (see §5). |
| Non-production — Dev, Test, UAT, sandbox clones; archive and long-tail file shares | **3** | Rebuild from backup. Do not pay for warm capacity here. |

**Tier assignment is a business decision, not an IT one.** Use `checklists/tier-assignment-workshop.md` to run that conversation and capture sign-off — you will need the signature at audit time.

---

## 4. The Exadata cost floor — read before promising Tier 2 or 3 for the database

Tiering compute is easy: stop the instance, stop paying for OCPUs. **Tiering Exadata is not.** ExaDB-D bills as *infrastructure* (fixed, by rack configuration) plus *OCPUs*. That means:

- There is **no zero-cost standby Exadata.** The infrastructure charge accrues whether or not the database is busy.
- What you *can* do is run the PHX VM cluster at a **minimum OCPU floor** and scale up during failover. OCPU scaling on ExaDB-D is online and completes in minutes — this is a real and meaningful lever, and it is the recommended Tier-1 posture.
- Scaling the standby to **zero** OCPUs stops redo apply, which converts your Tier 1 into a Tier 3 the moment you do it. Do not do this to save money and then report the old RPO.

**Consequence:** the "database is Tier 3 / restore-from-backup" option only genuinely saves money if you provision **no standby Exadata at all** and accept provisioning one during the disaster — which realistically adds hours and carries capacity risk in a regional event, exactly when Phoenix is busiest. The plan therefore recommends: **keep a standing PHX Exadata standby at minimum OCPU, and tier the *application* stack instead.** That is where the elastic money actually is.

If budget forces a non-Exadata standby, re-check assumption A5 (HCC) first — it may be a hard blocker.

---

## 5. Two honest caveats about these numbers

**Tier 0's 15-minute local RTO is real; the 60-minute cross-region figure is conditional.** It holds only if hostnames are preserved (`docs/01-architecture.md` §5.1). Without that, add 3–5 hours for `FND_CONC_CLONE.SETUP_CLEAN` plus AutoConfig across all tiers, and Tier 0 becomes a Tier 1 in practice.

**WRT estimates are the least reliable figures on this page** until you have run a full drill with the functional team. They are seeded from typical EBS recovery patterns, not from your instance. After the first drill (RB-04), replace them with measured values and re-derive MTD. Treat the current MTD column as a *design target*, not a commitment to the business, until that measurement exists.

---

## 6. What actually drives WRT (and how to shrink it)

Infrastructure gets you to "database open." These are what stand between that and "Finance signs off":

| WRT driver | Mitigation | Owner |
|---|---|---|
| Concurrent requests in-flight at failure — orphaned, part-complete, or duplicated on resubmit | `cmclean.sql` in the failover runbook; make critical concurrent programs **idempotent and restartable**; capture the running-request list on a schedule | EBS DBA + Dev |
| Inbound interface files consumed but not committed | Land **all** inbound files in Object Storage with bucket replication *before* processing; process from the replicated copy, never from an unreplicated local path | Integration |
| Outbound files generated but not transmitted | Write outbound to a replicated bucket; make transmission a separate, replayable step with a transmitted/not-transmitted ledger | Integration |
| Workflow Mailer duplicate or lost notifications | Document the accepted duplicate-send window; pre-brief users that some notifications may repeat after DR | EBS functional |
| Period-close in progress at failure | Freeze rule: **no cross-region failover during close** unless the business explicitly accepts it; if forced, follow the close-reconciliation checklist | Finance |
| Reconciliation and sign-off | Pre-built reconciliation report pack, rehearsed in every drill so it is routine rather than improvised | Finance |

The single highest-leverage change on this table is the interface pattern: **files land in replicated Object Storage before processing.** It converts an unbounded manual reconstruction into a bounded, scripted replay.
