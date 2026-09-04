# 07 — ITIL 4 Alignment and Terminology Conformance

This plan is written in the vocabulary of NIST SP 800-34 Rev. 1 (MTD, RTO, RPO) plus one
industry term that neither NIST nor ITIL defines and the plan therefore defines for itself
(Work Recovery Time). Its intended readers also
include people who think in ITIL 4 practice terms (service management, audit, risk) and
people who work from NIST and DoD instruments. This document does three things for them:

1. **§1–§2** map the plan's vocabulary to ITIL 4 and ISO 22301 terms, explicitly, without
   silently replacing one with the other, and (§1a) cross-walk the plan to NIST SP 800-34,
   NIST SP 800-53 Rev. 5, NIST CSF 2.0 and the DoD instruments that build on them.
2. **§3** reviews every existing document, runbook and checklist against ITIL 4 Service
   Continuity Management vocabulary and reports what *should* change. It does not rewrite
   the plan; each recommendation is a decision for the plan owner.
3. **§4** maps the ITIL 4 practices that this plan touches to the runbooks and artefacts
   that implement them, with the gaps stated.

> **Source honesty.** The ITIL 4 *Service Continuity Management* practice guide and the
> text of ISO 22301:2019 are paywalled and could not be read for this revision. Definitions
> below that carry a marker are quoted from the publicly available ITIL 4 Foundation
> glossary [1], NIST SP 800-34 Rev. 1 [2], or the ISO catalogue [7][8]. Terms that exist only
> in the paywalled practice guide (vital business function, maximum tolerable period of
> disruption, minimum business continuity objective, invocation) are marked as such and
> their definitions are paraphrased from general usage, not quoted.

---

## 1. Vocabulary mapping

| Term as used in this plan | Source and definition the plan relies on | ITIL 4 / ISO 22301 equivalent | Mapping and caveats |
|---|---|---|---|
| **MTD** — Maximum Tolerable Downtime | NIST SP 800-34 Rev. 1 §3.2.1, p. 17: "The MTD represents the total amount of time the system owner/authorizing official is willing to accept for a mission/business process outage or disruption and includes all impact considerations." [2][3] | **MTPD** — maximum tolerable period of disruption. The term is used in the ITIL 4 practice guide *(paywalled; not verified)* and was defined in ISO 22301:2012; a secondary source states the 2019 edition removed the term in favor of the more general "disruption" [9]. | **MTD ≈ MTPD.** Both are the business-owned ceiling on total outage. The plan keeps MTD because NIST is the citable, free source. Readers working to ISO 22301:2019 should treat the plan's MTD as the maximum period of disruption the business will accept. |
| **RTO** — Recovery Time Objective | NIST §3.2.1, p. 17: "RTO defines the maximum amount of time that a system resource can remain unavailable before there is an unacceptable impact on other system resources, supported mission/business processes, and the MTD." [2][4] | ITIL 4 glossary: "recovery time objective (RTO): The maximum acceptable period of time following a service disruption that can elapse before the lack of business functionality severely impacts the organization." [1] | **Same term, different boundary.** The plan's RTO ends at *technically available* (`docs/02-mtd-tiers.md` §1, the NIST sense). The ITIL 4 glossary RTO runs until the lack of *business functionality* hurts, which is the plan's MTD. An ITIL reader should read the plan's RTO as "technical RTO" and its MTD as the ITIL RTO. |
| **RPO** — Recovery Point Objective | NIST §3.2.1, p. 17: "The RPO represents the point in time, prior to a disruption or system outage, to which mission/business process data can be recovered … Unlike RTO, RPO is not considered as part of MTD." [2][5] | ITIL 4 glossary: "recovery point objective (RPO): The point to which information used by an activity must be restored to enable the activity to operate on resumption." [1] | Same term, compatible definitions. |
| **WRT** — Work Recovery Time | **An industry term not defined by NIST or ITIL; this plan defines it.** NIST does not define WRT; it says: "because it takes time to reprocess the data, that additional processing time must be added to the RTO to stay within the time limit established by the MTD." [2] WRT is the plan's name for that additional processing time. | No ITIL 4 or ISO 22301 equivalent. The nearest ITIL 4 idea is the period between technical recovery and the resumption of the vital business function at the minimum business continuity objective *(both terms practice-guide only; not verified)*. | Keep WRT. It is load-bearing for the ERP argument: for EBS the reconciliation and Finance sign-off often exceeds the technical RTO. Always present it as "the plan's decomposition MTD = RTO + WRT, consistent with NIST's reprocessing-time clause but not stated by NIST" — never as a NIST definition. |
| **Tier assignment workshop** (`checklists/tier-assignment-workshop.md`) | Plan-defined | **Business Impact Analysis (BIA)** — ITIL 4 glossary: "A key activity in the practice of service continuity management that identifies vital business functions and their dependencies." [1][6] | The workshop *is* a BIA. Recommend adding the term to the checklist title and to `docs/02` §3 (see §3 below). |
| **Core financials, Order Management, the database** (Tier 0 scope) | Plan-defined | **Vital business functions (VBFs)** — term appears in the BIA definition above [1]; the standalone definition is in the practice guide *(paywalled; not verified)*. | The Tier 0 scope list is the plan's VBF list. Name it as such once. |
| **Declare disaster** (RB-02 §0, `checklists/dr-authority-matrix.md`) | Plan-defined | **Invocation** of the continuity plan *(practice-guide term; not verified)*. ITIL 4 glossary defines the trigger: "disaster: A sudden unplanned event that causes great damage or serious loss to an organization. A disaster results in an organization failing to provide critical business functions for some predetermined minimum period of time." [1] | "Declare disaster" and "invoke the plan" are the same decision. Recommend using both words in RB-02 §0 and the authority matrix so ITIL readers find it. |
| **Posture** HOT / WARM / DRILL (RB-05 §1) | Plan-defined | **Recovery options** *(practice-guide term; not verified)*. Hot / warm / cold standby are the conventional names for the options. | The plan's postures are the selected recovery options at a given moment. Map once in RB-05 §1. |
| **DR drill** (RB-04) | Plan-defined | **Continuity exercising / testing** *(practice-guide term; not verified)*. | Same activity. Recommend the RB-04 title carry "(continuity exercise)". |
| **Disaster recovery (DR)** throughout | Plan-defined | ITIL 4 glossary: "disaster recovery plans: A set of clearly defined plans related to how an organization will recover from a disaster as well as return to a pre-disaster condition, considering the four dimensions of service management." [1] The governing practice is "service continuity management practice: The practice of ensuring that service availability and performance are maintained at a sufficient level in case of a disaster." [1] | The plan's runbooks are ITIL "disaster recovery plans" and the plan as a whole is the IT service continuity plan. Keep "DR" in the runbooks; state the relationship once in the README. |
| **Evidence** (`evidence/`), **attestation** | Plan-defined | Records demonstrating the practice's outcomes; ITIL 4 does not prescribe a name. | No change. |
| **CAB** — Change Advisory Board (RB-01 header, authority matrix) | Plan-defined | ITIL 4 uses **change authority** and the **change enablement** practice; a CAB is one form of change authority, not the practice itself. | Recommend "change authority (CAB)". |
| **MBCO** — minimum business continuity objective | **Not used in the plan.** | ITIL 4 practice guide and ISO 22301 term *(both not verified)*: the minimum level of service acceptable during a disruption. | **Gap.** The plan defines *when* each tier must be back but not *how much* of it. See §3 finding G1. |

Standards positioning, for the program-level reader:

- **ISO 22301** is the management-system standard for business continuity; the plan is one
  ICT-level artefact under such a system, not a substitute for it. The 2019 edition's terms
  and definitions supersede ISO 22300:2018 [8] and its definition of business continuity is
  "capability of an organization to continue the delivery of products and services within
  acceptable time frames at predefined capacity during a disruption" [8].
- **ISO/IEC 27031:2025** ("Cybersecurity — Information and communication technology
  readiness for business continuity") is the ICT-readiness guidance this plan sits under;
  the 2011 edition it replaced is withdrawn [7].
- **NIST SP 800-34 Rev. 1** remains the source for the plan's MTD / RTO / RPO framing [2].

### 1a. NIST and DoD crosswalk

Federal and defense reviewers work from NIST and DoD instruments rather than ITIL. The
table maps the plan's elements to those instruments. NIST rows are verified against the
published text [2][10][11][12]; the DoD rows are limited to what could be read, and the
entries say so.

| Plan element | ITIL 4 | NIST SP 800-34 Rev. 1 [2] | NIST SP 800-53 Rev. 5 CP family [10] | NIST CSF 2.0 [11] | Other NIST, DoD and federal |
|---|---|---|---|---|---|
| Tier workshop and MTD tiers (`docs/02`) | BIA | Step 2 "Conduct the business impact analysis (BIA)"; MTD/RTO/RPO definitions | CP-2 a.1 "Identifies essential mission and business functions and associated contingency requirements"; a.2 "Provides recovery objectives, restoration priorities, and metrics"; CP-2(3); CP-2(2) "Conduct capacity planning so that necessary capacity for information processing, telecommunications, and environmental support exists during contingency operations" (`docs/02` §4 capacity risk) | GOVERN — GV.OC-04 "Critical objectives, capabilities, and services that external stakeholders depend on or expect from the organization are understood and communicated"; GV.OC-05 "Outcomes, capabilities, and services that the organization depends on are understood and communicated" | FIPS 199 availability impact LOW / MODERATE / HIGH sets the categorization the tier answers [12]; CNSSI 1253 is the national-security-system categorization and control-selection instruction, whose attachments carry the overlays *(listing read; text login-gated)* [14]; NIST SP 800-34 footnote states mission-essential-function systems "must be able to meet the function's MTD of 12 hours or less per FCD-1" [2] |
| Preventive controls: SYNC standby, replication, immutable backups (`docs/01` §3–§4) | Risk reduction | Step 3 "Identify preventive controls" | CP-9 (system backup), CP-6 (alternate storage site) | PROTECT — PR.DS-11 "Backups of data are created, protected, maintained, and tested" | DoD Cloud Computing SRG impact levels govern where DoD data may reside *(portal not readable; secondary sources only)* [15] |
| Recovery strategy: Phoenix standby, postures, Full Stack DR (`docs/01`, RB-05) | Recovery option | Step 4 "Create contingency strategies"; cold / warm / hot site vocabulary | CP-7 (alternate processing site); CP-7(1) site "sufficiently separated from the primary processing site to reduce susceptibility to the same threats"; CP-8 "Establish alternate telecommunications services… for essential mission and business functions… when the primary telecommunications capabilities are unavailable" (assumption A6, DRG/remote-peering dependency, `docs/01` §1) | RECOVER | DoDI 8510.01: DoD systems "must be categorized in accordance with … CNSSI 1253 …, implement a corresponding set of security controls from NIST SP 800-53" *(2014 edition incl. Change 3 read from a Navy mirror; the 2022 reissue is not fetchable)* [16] |
| Runbooks RB-01 to RB-05 | Disaster recovery plans | Step 5 "Develop an information system contingency plan" (ISCP) | CP-2 a.3–a.7, b–f; CP-10 (system recovery and reconstitution); CP-10(2) "Implement transaction recovery for systems that are transaction-based" — what Data Guard redo apply provides for an ERP database | RC.RP-01 "The recovery portion of the incident response plan is executed once initiated from the incident response process" | DoDI 3020.26 *DoD Continuity Policy* *(cited by title and date only; not readable)* [17] |
| Drills and evidence (RB-04, `evidence/`); contingency training (`checklists/contingency-training.md`) | Exercising | Step 6 "Ensure plan testing, training, and exercises"; §3.5.1–§3.5.3 treat testing, training and exercises as distinct activities | CP-4 (contingency plan testing) — RB-04. CP-3 "Provide contingency training to system users consistent with assigned roles and responsibilities" — `checklists/contingency-training.md`, not RB-04: Rev. 5 lets exercise participation satisfy training only "at the discretion of the organization", and this plan exercises that discretion solely for the annual refresher of a person who performed their own role in a Level 2 or 3 drill (`checklists/contingency-training.md` §5). RB-04 §4's "primary DBA unavailable" inject tests the plan without the expert, not the expert without the plan, produces no per-person record, and runs only from the third drill as one of five rotating injects, so it evidences neither CP-3 a.1 (training within a set period of taking a role) nor SP 800-34 §3.5.2's "without aid of the actual ISCP document" outcome | GOVERN / IDENTIFY — ID.IM-02 "Improvements are identified from security tests and exercises, including those done in coordination with suppliers and relevant third parties" | RMF continuous monitoring (NIST SP 800-37 Rev. 2) [13] |
| Maintenance and drift detection (`docs/04` §5) | Continual improvement | Step 7 "Ensure plan maintenance" | CP-2 d–f | GOVERN — ID.IM-04 "Incident response plans and other cybersecurity plans that affect operations are established, communicated, maintained, and improved" | — |
| Cyber-event recovery (ransomware) | — | — | CP-10; IR family | RECOVER, RESPOND | NIST SP 800-184 *Guide for Cybersecurity Event Recovery* [18] |

**Design finding for federal or DoD use.** `us-ashburn-1` and `us-phoenix-1` are commercial
OC1 realm regions and carry no FedRAMP or DoD Impact Level authorization. Oracle's US
Government Cloud (OC2: `us-langley-1`, `us-luke-1`) "has obtained the following
authorizations: FedRAMP High; DISA Impact Level 4" and its tenancies "can't subscribe to
the commercial regions, or to the Oracle US Defense Cloud regions" [19][20]; Impact Level 5
is the US Defense Cloud (OC3: `us-gov-ashburn-1`, `us-gov-chicago-1`, `us-gov-phoenix-1`)
[21]. A federal or DoD workload must therefore re-base this plan onto one of those pairs, and
Full Stack DR availability in those realms was not checked in this revision.

---

## 2. What the plan should say about its own vocabulary

Recommended text for `docs/02-mtd-tiers.md` §1, after the definitions table (the plan owner
decides whether to adopt it):

> **For ITIL 4 and ISO 22301 readers.** MTD corresponds to the maximum tolerable period of
> disruption (MTPD) used in the ITIL 4 Service Continuity Management practice guide and in
> ISO 22301:2012 (both texts are paywalled and were not read for this plan; the 2019 edition
> of ISO 22301 reportedly dropped the term). RPO carries the same meaning in both
> vocabularies; the plan's RTO is the technical RTO, and the ITIL 4 glossary's RTO
> corresponds to the plan's MTD. Work Recovery Time is an industry term that neither NIST
> nor ITIL defines: this plan defines it as the reprocessing time that NIST says must be
> added to the RTO to stay within the MTD. The tier assignment workshop is a business impact analysis; the Tier 0
> scope is the list of vital business functions; "declare disaster" is invocation.

---

## 3. Conformance review of the existing documents

Method: every document, runbook and checklist was read against the ITIL 4 terms in §1.
Severity is about *reader confusion*, not correctness: the plan is technically consistent;
the question is whether an ITIL-literate reader will find what they expect.

| # | File | Current wording | ITIL 4 term | Recommendation | Severity |
|---|---|---|---|---|---|
| T1 | `README.md` | "IT Service Continuity Plan" in the title; "DR plan" in the body | service continuity management practice; disaster recovery plans [1] | Add one sentence stating the plan is the IT service continuity plan and the runbooks are its disaster recovery plans. | 🟡 |
| T2 | `docs/02-mtd-tiers.md` §1 | NIST now cited for MTD/RTO/RPO, ITIL 4 glossary cited for RTO/RPO, WRT declared the plan's term (done in this revision) | NIST definitions [2]; ITIL RTO/RPO [1] | Outstanding: adopt the §2 reader note and state MTD ≈ MTPD in docs/02 itself. | 🟡 |
| T3 | `docs/02-mtd-tiers.md` §3 and `checklists/tier-assignment-workshop.md` | "tier assignment", "which EBS component lands in which tier" | Business impact analysis; vital business functions [1] | Title the workshop "Tier assignment workshop (business impact analysis)"; call the Tier 0 scope "vital business functions" once. | 🟡 |
| T4 | `runbooks/RB-02-failover.md` §0; `checklists/dr-authority-matrix.md` | "Declare disaster", "DR Commander" | Invocation; disaster [1] | Use "declare disaster (invoke the continuity plan)". Role names are the organization's choice; ITIL 4 prescribes none. | 🟡 |
| T5 | `runbooks/RB-04-dr-drill.md` | "Non-Disruptive DR Drill", "Level 1/2/3" | Continuity exercising and testing *(practice guide)* | Add "(continuity exercise)" to the title; the three levels map well to component test → rehearsal → live test. | 🟢 |
| T6 | `runbooks/RB-05-replication-lifecycle.md` §1 | "Postures" | Recovery options *(practice guide)* | One sentence: "Each posture is a selected recovery option." | 🟢 |
| T7 | `runbooks/RB-01-switchover.md` header; `checklists/dr-authority-matrix.md` | "Change Advisory Board", "CAB" | Change enablement; change authority | "change authority (CAB)". | 🟢 |
| T8 | `docs/01-architecture.md` §3; `README.md` | Local SYNC standby described as "Local HA" alongside DR | Availability management (HA) versus service continuity management (DR) | Say explicitly: the intra-region SYNC leg with automatic failover is an *availability* control; the cross-region leg and everything in the runbooks is *continuity*. This split already exists in the design; name it. | 🟡 |
| T9 | `docs/04-monitoring.md` | "alarm", "alert" used interchangeably | Monitoring and event management: events, alerts | Harmless; optionally standardize on "alarm" (the OCI product term) and note it equals an ITIL alert. | 🟢 |
| T10 | `runbooks/RB-02-failover.md` §0 | "Incident detected" | Incident management: major incident | Say "major incident declared" as the entry condition to the decision gate; invocation is a decision taken *within* a major incident. | 🟡 |
| T11 | `docs/01-architecture.md` §1 (assumptions), `docs/02` §5 caveats | Risks stated as assumptions and caveats | Risk management: risk register | See gap G2. | 🟡 |
| T12 | All documents | No statement of how often the plan is reviewed | Continual improvement; ISO 22301 review requirement | See gap G3. | 🟡 |
| T13 | `README.md`, `docs/01-architecture.md` §2–§3 ("Local HA"); `docs/02-mtd-tiers.md` §2 ("RTO ≤ 15 min local") | The intra-region SYNC leg's automatic failover is described as if it alone restores service after an AD-1 loss | Availability management: the practice covers the service, not one component of it | State explicitly that the local-region high-availability boundary requires a **two-AD application tier** (`WIN-EBSWEB02` and the stopped `WIN-EBSCM02` twin in AD-2, `WIN-BI01` in AD-2, a load balancer spanning both ADs) as well as the SYNC database standby; the database's automatic local failover does not by itself restore application availability if the app tier survives in only one AD. This sharpens T8's boundary (see G4). | 🟠 |
| T14 | `docs/01-architecture.md` §3 ("RPO 0"); `docs/02-mtd-tiers.md` §2; `scripts/dataguard/tnsnames-tuning.md` §4 | RPO 0 on the local leg is stated without the condition under which it holds | Service continuity management: a recovery point objective is a target, and a target's stated conditions are part of stating it | Say wherever RPO 0 appears that it holds only while the configuration is synchronized: an unset `NetTimeout` leaves an AD-2 network fault's stall duration undefined, and fast-start failover cannot occur once the target standby is unsynchronized (`scripts/dataguard/tnsnames-tuning.md` §4; alarmed in `docs/04-monitoring.md` §1–§2). | 🟠 |

### Gaps (things ITIL 4 expects that the plan does not yet contain)

| # | Gap | Why it matters | Recommendation |
|---|---|---|---|
| G1 | **No minimum business continuity objective per tier.** The tiers say *when* each scope must be back, not *how much of it* is acceptable while WRT runs. | Finance signs off MTD; an auditor working to ISO 22301 will ask what the business agreed to operate with in the meantime (for example: order entry and cash application available, batch and reporting deferred). | Add an "MBCO" row to the tier table in `docs/02` §2 and a column to the workshop output table, populated in the BIA workshop. |
| G2 | **No risk register.** Material assumptions (`docs/01` §1) and design risks (Exadata floor, HCC, RTT, egress) are scattered. | ITIL 4 risk management expects risks to be identified, assessed, owned and reviewed. | Add `checklists/risk-register.md` with owner, likelihood, impact and treatment; seed it from the [MATERIAL] assumptions and the unverified statements listed in each document's References section. |
| G3 | **No review and maintenance cadence.** The workshop note says "re-run annually"; nothing says when the plan itself is reviewed. | Continuity plans decay; ISO 22301 requires planned review. | Add a "Plan maintenance" section to the README: annual review, review after every drill, after any material change (acquisition, re-platform, new regulation), and after any invocation. |
| G4 | **No explicit availability-versus-continuity boundary** (T8, T13). | The two practices have different owners and different measures (availability % versus MTD); T13 shows the boundary also has an unstated dependency (a two-AD app tier) that the local RTO claim relies on. | One paragraph in `docs/01` §3 covering both the ownership split and the two-AD app-tier dependency. |

---

## 4. ITIL 4 practice alignment

Purposes are paraphrased where the glossary does not define the practice; only the service
continuity management practice definition is quoted [1].

| ITIL 4 practice | Purpose (as it applies here) | Where this plan implements it | Artefacts and evidence | Gaps |
|---|---|---|---|---|
| **Service continuity management** | "The practice of ensuring that service availability and performance are maintained at a sufficient level in case of a disaster." [1] | The whole plan. BIA: `checklists/tier-assignment-workshop.md`. Recovery options: `docs/02` §2, RB-05 §1. Plans: RB-01 (planned switchover), RB-02 (invocation and failover), RB-03 (return), RB-05 (lifecycle). Exercising: RB-04. | Signed tier attestation; drill timing sheets; RPO attestations; posture log; decommission log. | G1 (MBCO), G3 (review cadence). |
| **Availability management** | Ensure services deliver agreed availability. | The intra-region SYNC standby with Fast-Start Failover (`docs/01` §3, §4.1) is an availability control, not a continuity one; the visualization tier reading the Active Data Guard standby (`docs/01` §4.5) is availability-driven daily proof that the standby works. | Data Guard Broker health (`scripts/dataguard/dg-health.sh`); `docs/04` alarms on the SYNC leg. | G4: name the boundary. No availability targets (%) are stated; they belong in a separate SLA document. |
| **Change enablement** | Ensure changes are assessed and authorized. | RB-01 requires change-authority approval; RB-03 requires change and business approval; RB-05 §5 requires written sign-off; every guarded script writes an evidence record, and each accepts a change reference (`--reason` on posture, scaling and steering; `--ticket` on the three storage one-way doors and on decommission). `docs/04` §5 drift detection catches unauthorised change. | Posture log, OCPU scale log, traffic steering log, decommission log. | T7 wording. Emergency change: RB-02 states that invocation does not wait for the change authority; say explicitly that this is a pre-authorized emergency change, recorded after the fact. |
| **Incident management** | Restore normal service as quickly as possible. | RB-02 §0 decision gate; the authority matrix's standing decisions; RB-02 §7 contingency branches. | Data-loss statement (`capture-lag-snapshot.sh`); in-flight request capture. | T10: the major-incident entry condition. Post-incident review exists (RB-03 §5) but has no template. |
| **Monitoring and event management** | Observe services and record and report state changes. | `docs/04` §1–§3: silent-failure catalog, alarm definitions, readiness dashboard; "alarm on the absence of signal". | OCI Monitoring alarms; `check-replication-health.sh` exit codes; RPO attestation. | Alarm definitions as code are planned build-out (README §Status). |
| **Risk management** | Understand and handle risks. | Material assumptions (`docs/01` §1); explicit caveats (`docs/02` §5); one-way-door catalog (`docs/03` §2); freeze rules (period close, open `adop` cycle). | Unverified-statement lists in each document's References section. | G2: no register, no owners, no review. |
| **Service level management** | Set and monitor business-facing targets. | The tier table *is* the business-facing target set; measured RTO/WRT replace design targets after drills (RB-04 §5). | Drill timing sheet comparison-to-target table. | Targets are not yet in an SLA document; MBCO missing (G1). |
| **Information security management** | Protect the organization's information. | Immutable backups with retention lock (`docs/01` §4.1); Vault key replication; `evidence/` sensitivity guidance. | Retention-lock configuration; evidence handling decision. | Out of scope here beyond what the continuity design needs. |

---

## 5. Decisions requested from the plan owner

1. Adopt the §2 reader note into `docs/02` §1 (recommended).
2. Apply the 🔴 and 🟡 wording changes in §3 (T1–T4, T8, T10–T12); leave 🟢 items to
   taste.
3. Close gaps G1–G4, in that order; G1 needs the business in the room and should be folded
   into the next tier workshop.

None of these change the plan's technical content. They change how it reads to the audit,
risk and service-management audience that an IT service continuity plan exists to satisfy.

---

## References

This document is a synthesis: every statement about product behavior or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *Glossary — ITIL 4 Foundation Official Training Materials.* PeopleCert (copy hosted by a
   training provider), undated, accessed 2026-09-01.
   <https://igen.nl/wp-content/uploads/2024/10/ITIL-4-Foundation_Glossary_Digital.pdf> —
   Supports: definitions of service continuity management practice, business impact
   analysis, recovery time objective, recovery point objective, disaster, disaster recovery
   plans (§1, §3, §4). Note: the ITIL 4 *Service Continuity Management* practice guide, which
   defines vital business function, MTPD, MBCO and invocation, is paywalled. Unverifiable by
   URL: paywalled (PeopleCert/AXELOS). Those four terms are paraphrased, not quoted.
2. *NIST Special Publication 800-34 Rev. 1, Contingency Planning Guide for Federal
   Information Systems.* National Institute of Standards and Technology, May 2010 (errata
   2010-11-11), accessed 2026-09-01.
   <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf> —
   Supports: MTD, RTO and RPO definitions (§3.2.1, p. 17; Appendix G, p. G-2); "RPO is not
   considered as part of MTD"; reprocessing time "must be added to the RTO to stay within the
   time limit established by the MTD" (§1); §3.5.1–§3.5.3 as distinct activities and §3.5.2's
   annual cadence, "shortly thereafter" for new appointees and "without aid of the actual ISCP
   document" outcome (p. 28) (§1a). The document does not define Work Recovery Time.
3. *Maximum Tolerable Downtime.* NIST Computer Security Resource Center glossary, accessed
   2026-09-01. <https://csrc.nist.gov/glossary/term/maximum_tolerable_downtime> — Supports:
   the glossary form of the MTD definition attributed to SP 800-34 Rev. 1 (§1).
4. *Recovery Time Objective.* NIST CSRC glossary, accessed 2026-09-01.
   <https://csrc.nist.gov/glossary/term/recovery_time_objective> — Supports: RTO (§1).
5. *Recovery Point Objective.* NIST CSRC glossary, accessed 2026-09-01.
   <https://csrc.nist.gov/glossary/term/Recovery_Point_Objective> — Supports: RPO (§1).
6. *ITIL V4 Glossary* (third-party copy). pdfcoffee.com, undated, accessed 2026-09-01.
   <https://pdfcoffee.com/itil-v4-glossary-pdf-free.html> — Supports: the fetched page
   exposes only the glossary's term index (business impact analysis, recovery point
   objective, recovery time objective, among others); the definition sentences are not in
   the page text, so the wording in [1] cannot be cross-checked against it. Corroborates
   existence of the terms only (§1).
7. *ISO/IEC 27031:2025 — Cybersecurity — Information and communication technology readiness
   for business continuity.* ISO committee catalogue, edition 2, May 2025, accessed
   2026-09-01. <https://committee.iso.org/standard/80975.html> — Supports: title and scope;
   that the 2011 edition (<https://committee.iso.org/standard/44374.html>) is withdrawn and
   replaced (§1). The standard's text is paywalled.
8. *ISO 22301:2019 redline preview.* iTeh Standards (12-page sample), accessed 2026-09-01.
   <https://cdn.standards.iteh.ai/samples/75106/5e083fd428f54407a6aae14cb574019c/ISO-22301-2019.pdf>
   — Supports: "The terms and definitions given below supersede those given in ISO
   22300:2018" and the definition of business continuity (clause 3.3) (§1). The clauses
   defining MTPD, MBCO, RTO and RPO are not in the preview. Unverifiable by URL: paywalled
   (ISO); the ISO Online Browsing Platform returned HTTP 403 to automated fetch.
9. *ISO 22301:2019 vs. previous versions: What's changed?* Paul Kirvan, TechTarget,
   2020-09-29, accessed 2026-09-01.
   <https://www.techtarget.com/searchdisasterrecovery/tip/ISO-223012019-vs-previous-versions-Whats-changed>
   — Supports: the secondary-source statement that the 2019 edition removed the term
   "maximum tolerable period of disruption" (§1). Secondary source; not the standard.

10. *Security and Privacy Controls for Information Systems and Organizations, NIST SP 800-53
    Rev. 5 (Update 1).* NIST, September 2020 with updates through 2020-12-10, accessed
    2026-09-01. <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf>
    — Supports: CP-2, CP-2(2), CP-2(3), CP-3, CP-4, CP-6, CP-7, CP-7(1), CP-8, CP-9, CP-10,
    CP-10(2) wording (§1a); CP-3 a.1 "Within [Assignment: organization-defined time period] of
    assuming a contingency role or responsibility" and the CP-3 Discussion sentence "At the
    discretion of the organization, participation in a contingency plan test or exercise,
    including lessons learned sessions subsequent to the test or exercise, may satisfy
    contingency plan training requirements" (§1a).
11. *The NIST Cybersecurity Framework (CSF) 2.0, NIST CSWP 29.* NIST, 2024-02-26, accessed
    2026-09-01. <https://nvlpubs.nist.gov/nistpubs/CSWP/NIST.CSWP.29.pdf> — Supports: the six
    Functions, RC.RP / RC.RP-01, GV.OC-04, GV.OC-05, ID.IM-02, ID.IM-04, PR.DS-11 (§1a).
12. *Standards for Security Categorization of Federal Information and Information Systems,
    FIPS PUB 199.* NIST, February 2004, accessed 2026-09-01.
    <https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.199.pdf> — Supports: availability
    definition and LOW / MODERATE / HIGH impact levels (§1a).
13. *Risk Management Framework for Information Systems and Organizations, NIST SP 800-37
    Rev. 2.* NIST, December 2018, accessed 2026-09-01.
    <https://csrc.nist.gov/pubs/sp/800/37/r2/final> — Supports: RMF lifecycle including
    continuous monitoring (§1a).
14. *CNSS Instructions listing (CNSSI 1253, Security Categorization and Control Selection for
    National Security Systems).* Committee on National Security Systems, listing entries dated
    2022–2023, accessed 2026-09-01. <https://www.cnss.gov/CNSS/issuances/Instructions.cfm> —
    Supports: existence of CNSSI 1253 (release date 08/01/2022) (§1a). The listing says nothing
    about NIST SP 800-53 Rev. 5 alignment; that clause is not claimed in the body text.
    Unverifiable by URL: the document download sits behind a login/certificate wall; only the
    listing was read.
15. *DISA Issues Cloud Computing Security Requirements Guide.* ExecutiveGov, 2024-06-25,
    accessed 2026-09-01.
    <https://www.executivegov.com/articles/disa-issues-cloud-computing-security-requirements-guide>
    — Supports: that the CC SRG "reflects the transition to NIST 800-53 Rev 5" (§1a).
    Secondary source. Unverifiable by URL: the DISA document portal is not readable by
    automated fetch.
16. *DoD Instruction 8510.01, Risk Management Framework (RMF) for DoD Information Technology
    (IT).* DoD CIO, 2014-03-12 incorporating Change 3 of 2020-12-29 (Navy-hosted copy),
    accessed 2026-09-01. <https://www.doncio.navy.mil/Filehandler.ashx?id=18360> — Supports:
    the categorization-and-controls sentence quoted in §1a. The 2022 reissue on esd.whs.mil
    returned HTTP 403; its wording is not verified.
17. *DoD Instruction 3020.26, DoD Continuity Policy.* DoD, 2024-06-04 (title and date from
    the issuing site's search listing only). Unverifiable by URL: HTTP 403 to automated fetch
    (esd.whs.mil) and an empty bot-challenge response from the mirror. Cited by title only
    (§1a). <https://www.esd.whs.mil/Portals/54/Documents/DD/issuances/dodi/302026p.PDF>
18. *Guide for Cybersecurity Event Recovery, NIST SP 800-184.* NIST, December 2016, accessed
    2026-09-01. <https://csrc.nist.gov/pubs/sp/800/184/final> — Supports: recovery planning
    for cyber events (§1a).
19. *Regions and Availability Domains.* Oracle Cloud Infrastructure Documentation, © 2026,
    accessed 2026-09-01. <https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm>
    — Supports: `us-ashburn-1` and `us-phoenix-1` are realm OC1 (§1a).
20. *Oracle US Government Cloud.* Oracle Cloud Infrastructure Documentation, © 2026, accessed
    2026-09-01. <https://docs.oracle.com/iaas/Content/General/Concepts/govfedramp.htm> —
    Supports: FedRAMP High and DISA IL4 authorizations; OC2 regions; realm isolation (§1a).
21. *Oracle US Defense Cloud.* Oracle Cloud Infrastructure Documentation, © 2026, accessed
    2026-09-01. <https://docs.oracle.com/iaas/Content/General/Concepts/govfeddod.htm> —
    Supports: Impact Level 5 and the OC3 regions (§1a).

### Unverified statements

- The definitions of vital business function, maximum tolerable period of disruption,
  minimum business continuity objective, invocation and recovery options are paraphrased
  from general ITIL usage; the practice guide that defines them could not be read.
- Whether ISO 22301:2019 still uses MTPD rests on a secondary source [9].
- The DoD Cloud Computing SRG's current version and impact-level definitions rest on secondary
  sources; DoDI 3020.26 and DoDI 8500.01 could not be read at all.

[1]: https://igen.nl/wp-content/uploads/2024/10/ITIL-4-Foundation_Glossary_Digital.pdf "ITIL 4 Foundation Glossary — PeopleCert"
[2]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf "NIST SP 800-34 Rev. 1"
[3]: https://csrc.nist.gov/glossary/term/maximum_tolerable_downtime "NIST CSRC glossary — Maximum Tolerable Downtime"
[4]: https://csrc.nist.gov/glossary/term/recovery_time_objective "NIST CSRC glossary — Recovery Time Objective"
[5]: https://csrc.nist.gov/glossary/term/Recovery_Point_Objective "NIST CSRC glossary — Recovery Point Objective"
[6]: https://pdfcoffee.com/itil-v4-glossary-pdf-free.html "ITIL V4 Glossary (third-party copy)"
[7]: https://committee.iso.org/standard/80975.html "ISO/IEC 27031:2025 — ISO committee catalogue"
[8]: https://cdn.standards.iteh.ai/samples/75106/5e083fd428f54407a6aae14cb574019c/ISO-22301-2019.pdf "ISO 22301:2019 redline preview — iTeh"
[9]: https://www.techtarget.com/searchdisasterrecovery/tip/ISO-223012019-vs-previous-versions-Whats-changed "ISO 22301:2019 vs. previous versions — TechTarget"
[10]: https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf "NIST SP 800-53 Rev. 5"
[11]: https://nvlpubs.nist.gov/nistpubs/CSWP/NIST.CSWP.29.pdf "NIST CSF 2.0 (CSWP 29)"
[12]: https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.199.pdf "FIPS PUB 199"
[13]: https://csrc.nist.gov/pubs/sp/800/37/r2/final "NIST SP 800-37 Rev. 2"
[14]: https://www.cnss.gov/CNSS/issuances/Instructions.cfm "CNSS Instructions listing"
[15]: https://www.executivegov.com/articles/disa-issues-cloud-computing-security-requirements-guide "DISA Cloud Computing SRG — ExecutiveGov"
[16]: https://www.doncio.navy.mil/Filehandler.ashx?id=18360 "DoDI 8510.01 (Navy-hosted copy)"
[17]: https://www.esd.whs.mil/Portals/54/Documents/DD/issuances/dodi/302026p.PDF "DoDI 3020.26 (not fetchable)"
[18]: https://csrc.nist.gov/pubs/sp/800/184/final "NIST SP 800-184"
[19]: https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm "OCI Regions and Availability Domains"
[20]: https://docs.oracle.com/iaas/Content/General/Concepts/govfedramp.htm "Oracle US Government Cloud"
[21]: https://docs.oracle.com/iaas/Content/General/Concepts/govfeddod.htm "Oracle US Defense Cloud"
