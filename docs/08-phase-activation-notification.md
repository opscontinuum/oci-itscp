# 08 — Phase 1: Activation and Notification

**The phase that decides.** Nothing in this phase restores service. Its entire output is a
decision — *is this a disaster?* — plus the notifications that put the right people on the
bridge before the answer arrives.

NIST SP 800-34 Rev. 1 requires an ISCP to contain an "Overview of three phases" in its
concept-of-operations section: "The ISCP recovery is implemented in three phases: (1)
Activation and Notification, (2) Recovery, and (3) Reconstitution" (§4.1, printed page 35)
[1]. This plan's runbooks are organised by *scenario* — switchover, failover, failback,
drill — not by phase, so a reader arriving from the NIST structure cannot find the phases
without a map. `docs/08`, `docs/09` and `docs/10` are that map, one per phase.

> ### These documents route; they do not instruct
>
> Every procedural step lives in a runbook or a checklist. If you are executing, go to the
> file named in the routing table and work from there. Reading this document during an
> incident is a sign you opened the wrong file — start at
> [`runbooks/RB-02-failover.md`](../runbooks/RB-02-failover.md) §0.

---

## 1. What NIST means by this phase

> "The Activation and Notification Phase defines initial actions taken once a system
> disruption or outage has been detected or appears to be imminent. This phase includes
> activities to notify recovery personnel, conduct an outage assessment, and activate the
> plan. At the completion of the Activation and Notification Phase, ISCP staff will be
> prepared to perform recovery measures to restore system functions."
> — §4.2, printed page 36 [1]

Three activities, in NIST's order: **activation criteria and procedure** (§4.2.1),
**notification procedures** (§4.2.2), **outage assessment** (§4.2.3). This plan performs all
three, but not in that order — see §3.

---

## 2. Entry and exit

| | Condition | Where it is defined |
|---|---|---|
| **Entry** | A major incident is declared against the EBS service, or an event is *imminent* (an announced weather threat, a disclosed vulnerability with active exploitation, a notified upstream outage). Detection comes from the alarms in `docs/04` §2 or from a human. | [`docs/04-monitoring.md`](04-monitoring.md) §1–§2 |
| **Exit** | Either the plan is **activated** (disaster declared, Recovery Phase begins) or it is **not** (the incident continues under normal incident management). Both are valid exits. The phase is complete when the decision is made and recorded, not when service returns. | [`runbooks/RB-02-failover.md`](../runbooks/RB-02-failover.md) §0 |

**The non-activation exit is the common one and this plan treats it as a first-class
outcome.** Most major incidents are resolved in place. RB-02 §0 exists to stop a reflexive
failover, not to authorise one.

---

## 3. The three activities, and what performs them here

| NIST activity | What performs it in this plan | File and section |
|---|---|---|
| **Activation criteria and procedure** (§4.2.1) — "The ISCP should be activated if one or more of the activation criteria for that system are met" [1] | The 10-minute decision gate. Criteria are expressed as a comparison of *estimated repair time* against *remaining MTD budget*, per the tier the affected scope sits in. | [`RB-02`](../runbooks/RB-02-failover.md) §0; tiers in [`docs/02`](02-mtd-tiers.md) §2–§3 |
| **Designated authority** — "Only one individual should have this authority, and a successor should be clearly identified" (footnote 31, printed page 36) [1] | Declaration authority and its ordered succession. | [`checklists/roles-and-responsibilities.md`](../checklists/roles-and-responsibilities.md) §2, §4; standing decisions in [`checklists/dr-authority-matrix.md`](../checklists/dr-authority-matrix.md) |
| **Notification procedures** (§4.2.2) — call tree, primary and alternate contact methods, what to do when someone cannot be reached [1] | The call tree, the roster, the script for what to say, and the unreachable-contact procedure. | [`checklists/contact-roster.md`](../checklists/contact-roster.md) §1–§4 |
| **External and interconnected-system POCs** (§4.2.2) [1] | One row per interconnection; the partners whose files RB-02 §6 replays. | [`checklists/contact-roster.md`](../checklists/contact-roster.md) §5 |
| **Outage assessment** (§4.2.3) — cause, potential for further damage, equipment status, items to replace, "Estimated time to restore normal services" [1] | The assessment procedure that produces the repair estimate the gate consumes. | [`checklists/outage-assessment.md`](../checklists/outage-assessment.md) |

### 3.1 This plan runs assessment and notification concurrently, not sequentially

NIST's §4.2.2 describes a sequence: notify the Outage Assessment Team, assess, then "the
appropriate recovery and system support personnel should be notified" (printed page 36) [1].

This plan does not wait. RB-02 §0 gives the decision ten minutes total, and
`checklists/outage-assessment.md` §1 budgets the assessment inside that window; the call
tree in `contact-roster.md` §1 is started at the *same* time, on the reasoning that
assembling people is reversible and cheap, whereas a serial assessment-then-notify path
spends the MTD budget before anyone has joined the bridge. Tier 0's MTD is two hours
(`docs/02` §2); a fifteen-minute serial notification chain is 12.5% of it.

*(Unverified: this ordering is this plan's engineering judgement. NIST describes the
sequential form and does not address running the two concurrently; nothing in §4.2 forbids
it, and nothing read in this revision endorses it.)*

### 3.2 Assessment is scoped to a cloud estate, and that removes most of NIST's list

NIST's minimum assessment areas assume a physical site the assessor can walk into —
"structural integrity of computer room, condition of electric power, telecommunications, and
heating, ventilation and air-conditioning [HVAC]" (§4.2.3, printed page 38) [1]. This plan
protects a workload in OCI regions the operator has no physical access to. The equivalent
signals are control-plane and monitoring state, not a physical walkthrough.
`checklists/outage-assessment.md` §3 states which of NIST's areas are answerable, which are
answered by Oracle rather than by the operator, and which are genuinely not applicable —
with the reason in each case, rather than a silent omission.

---

## 4. Where this plan has no equivalent, and why

| NIST element | Status here | Reason |
|---|---|---|
| "Instructions to prepare for relocation for estimated time period" (§4.2.2, printed page 38) [1] | **Not applicable** | Recovery is to `us-phoenix-1`, not to a physical alternate site. No person relocates. Already recorded as not applicable in [`contact-roster.md`](../checklists/contact-roster.md) §4. |
| Transportation and relocation team (§3.4.6, printed page 26) [1] | **Not applicable** | Same reason. |
| Shipment of backup media from offsite storage (§4.3.1, printed page 39) [1] | **Not applicable** | Backups are in Autonomous Recovery Service and Object Storage, reachable over the network. See [`docs/03`](03-replication-matrix.md) §1. |
| Media relations and legal affairs teams (§3.4.6) [1] | **Out of scope** | Organisation-wide functions, not system-level ones. Named as escalation destinations in [`roles-and-responsibilities.md`](../checklists/roles-and-responsibilities.md) §5, not staffed by this plan. |

---

## 5. If you are in this phase right now

1. [`runbooks/RB-02-failover.md`](../runbooks/RB-02-failover.md) §0 — the gate. Start here.
2. [`checklists/outage-assessment.md`](../checklists/outage-assessment.md) — run it in parallel; it produces the estimate §0 needs.
3. [`checklists/contact-roster.md`](../checklists/contact-roster.md) §1 — start the call tree now, not after the decision.
4. [`checklists/pre-failover-precheck.md`](../checklists/pre-failover-precheck.md) — only once the gate says *declared*.

Then go to [`docs/09-phase-recovery.md`](09-phase-recovery.md).

---

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *NIST Special Publication 800-34 Rev. 1, Contingency Planning Guide for Federal
   Information Systems.* National Institute of Standards and Technology, May 2010 (errata
   2010-11-11), accessed 2026-09-02.
   <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf> —
   Supports: §4.1, printed page 35 (PDF page 49): "Overview of three phases. The ISCP
   recovery is implemented in three phases: (1) Activation and Notification, (2) Recovery,
   and (3) Reconstitution" (introduction); §4.2, printed page 36 (PDF page 50): "The
   Activation and Notification Phase defines initial actions taken once a system disruption
   or outage has been detected or appears to be imminent. This phase includes activities to
   notify recovery personnel, conduct an outage assessment, and activate the plan. At the
   completion of the Activation and Notification Phase, ISCP staff will be prepared to
   perform recovery measures to restore system functions" (§1); §4.2.1, printed page 36:
   "The ISCP should be activated if one or more of the activation criteria for that system
   are met", with criteria that "may be based on: Extent of any damage to the system (e.g.,
   physical, operational, or cost); Criticality of the system to the organization's mission
   … and Expected duration of the outage lasting longer than the RTO" (§3); footnote 31,
   printed page 36: "The designated authority (typically a senior manager or CIO) has the
   authority to activate the contingency plan. … Only one individual should have this
   authority, and a successor should be clearly identified to assume that responsibility if
   necessary" (§3); §4.2.2, printed page 36: "Following the outage or disruption,
   notification should be sent to the Outage Assessment Team so that it may determine the
   status of the situation and appropriate next steps. … When outage assessment is complete,
   the appropriate recovery and system support personnel should be notified" (§3, §3.1);
   §4.2.2, printed page 37: "The notification strategy should define procedures to be
   followed in the event that specific personnel cannot be contacted. … A common manual
   notification method is a call tree" (§3); §4.2.2, printed page 38: notification content
   list including "Instructions to prepare for relocation for estimated time period (if
   applicable)" (§4); §4.2.3, printed page 38 (PDF page 52): "The outage assessment should
   be completed as quickly as the given conditions permit, with personnel safety remaining
   the highest priority", and the minimum areas list including "Status of physical
   infrastructure (e.g., structural integrity of computer room, condition of electric power,
   telecommunications, and heating, ventilation and air-conditioning [HVAC])" and "Estimated
   time to restore normal services" (§3, §3.2); §3.4.6, printed page 26 (PDF page 40): team
   list including "Transportation and relocation team", "Media relations team" and "Legal
   affairs team" (§4); §4.3.1, printed page 39 (PDF page 53): "these items may include
   shipment of data backup media from offsite storage, hardware, copies of the recovery plan,
   and software programs" (§4).

### Unverified statements

- Running outage assessment and the call tree concurrently rather than sequentially (§3.1) is
  this plan's engineering judgement. NIST describes the sequential form; no source read in
  this revision addresses the concurrent form either way.
- The ten-minute budget for the decision gate, and the share of the Tier 0 MTD that a
  sequential notification chain would consume (§3.1), are this plan's own figures, derived
  from the tiers in `docs/02` §2. They are design targets, not measurements, until a Level 2
  drill times them (`runbooks/RB-04-dr-drill.md` §5).
- The claim that assembling people is "reversible and cheap" relative to spending MTD budget
  (§3.1) is a judgement about this organisation's incident culture, not a sourced statement.

[1]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf "NIST SP 800-34 Rev. 1"
