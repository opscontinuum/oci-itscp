# Roles and Responsibilities

Who is who, who backs them up, and who does what in each phase.

> **This file and [`dr-authority-matrix.md`](dr-authority-matrix.md) answer different
> questions and neither replaces the other.** The authority matrix answers *who may decide
> this action, without waiting for whom* — it is a decision-rights table. This file answers
> *who holds each role, who succeeds them, and what each team is accountable for across the
> three phases*. During an incident you will read the matrix. Before an incident you fill in
> this one.

NIST SP 800-34 Rev. 1 requires the roles section to present "the overall structure of
contingency teams, including the hierarchy and coordination mechanisms and requirements among
the teams" (§4.1, printed page 35) [1]. Its plan template asks, "At a minimum, a role should
be established for a system owner or business unit point of contact, a recovery coordinator,
and a technical recovery point of contact" (Appendix A.2, printed page A.2-6) [1].

---

## 1. Leadership roles

NIST's template names two leadership roles: an **ISCP Director**, "who has overall management
responsibility for the plan", and an **ISCP Coordinator**, "who is responsible to oversee
recovery and reconstitution progress, initiate any needed escalations or awareness
communications, and establish coordination with other recovery and reconstitution teams as
appropriate" (Appendix A.2, printed page A.2-6) [1].

| NIST role | Name used in this plan | Accountable for | Held by |
|---|---|---|---|
| **Designated authority** (footnote 31, printed page 36) [1] | **DR Commander** | The declaration decision, and only that decision. Does not run the recovery | `{name}` |
| **ISCP Director** | **DR Commander** (same person) | Overall management responsibility for the plan; owns the annual review | `{name}` |
| **ISCP Coordinator** | **DR Coordinator** | Running the recovery: sequence, escalations, cross-team coordination, status to the bridge | `{name}` |
| **Information System Owner** | **Application owner (EBS)** | The system, its interconnections, and the reassessment judgment at Reconstitution | `{name}` |
| **Business unit POC** | **Business owner** | Tier assignment, the MTD targets, and the RPO-breach decision (RB-02 §7d) | `{name}` |
| **Technical recovery POC** | **DBA on-call** | The database role transition and the data-currency evidence | `{name}` |

**The DR Commander declares; the DR Coordinator recovers.** Keeping these separate is
deliberate: the person deciding whether the estimated repair time beats the remaining MTD
budget should not simultaneously be running the storage activation sequence. When one person
holds both, the decision gate in [`RB-02`](../runbooks/RB-02-failover.md) §0 gets compressed
into whatever the recovery work leaves time for.

*(Unverified: the split is this plan's engineering judgment. NIST names both roles and does
not state whether one individual may hold both.)*

---

## 2. Declaration authority and line of succession

> "Only one individual should have this authority, and a successor should be clearly
> identified to assume that responsibility if necessary."
> — footnote 31, printed page 36 [1]

**One person holds declaration authority at any moment.** The succession list is ordered, and
authority passes to the next name only when the one above is unreachable by both contact
methods in [`contact-roster.md`](contact-roster.md) §2a after the interval below.

| Order | Role | Name | Passes after | Reachable via |
|---|---|---|---|---|
| 1 | DR Commander | `{name}` | — | `{primary}` / `{alternate}` |
| 2 | Deputy DR Commander | `{name}` | 10 min unreachable | `{primary}` / `{alternate}` |
| 3 | CIO | `{name}` | 10 min unreachable | `{primary}` / `{alternate}` |
| 4 | Duty executive (rota) | `{name}` | 15 min unreachable | `{primary}` / `{alternate}` |

**The clock does not stop while succession runs.** Ten minutes spent failing to reach the
Commander is ten minutes of the MTD budget, and the gate in RB-02 §0 is a ten-minute gate in
total. Start the call tree down two levels at once rather than serially — see
[`contact-roster.md`](contact-roster.md) §3.

**Succession is for unreachability, not disagreement.** If the DR Commander is reachable and
decides not to declare, that is the decision. Escalating to the next name to get a different
answer is not succession; the route for disagreement is the business owner and the standing
decisions in [`dr-authority-matrix.md`](dr-authority-matrix.md).

*(Unverified: the 10- and 15-minute intervals are this plan's engineering judgment, chosen
to fit inside the RB-02 §0 gate. No source read in this revision specifies succession
intervals.)*

---

## 3. Teams

NIST lists fifteen candidate team types and is explicit that they are candidates: a strategy
"will require some or all of the following groups", and "The size of each team, team titles,
and hierarchy designs depend on the organization" (§3.4.6, printed page 26) [1].

A cloud environment with no physical access removes several outright. Stated with reasons rather
than silently dropped:

| NIST team (§3.4.6) [1] | Here | Lead | Notes |
|---|---|---|---|
| Management team (incl. ISCP Coordinator) | **Command** | DR Coordinator | §1 |
| Outage assessment team | **Assessment** | Infra on-call | [`outage-assessment.md`](outage-assessment.md) |
| Database recovery team | **Database** | DBA on-call | RB-02 §3 |
| Server recovery team | **Application tier** | Windows/infra on-call | RB-02 §5 |
| Operating system administration team | folded into **Application tier** | Windows/infra on-call | Same people; no separate OS team for five nodes |
| LAN/WAN recovery team | folded into **Network** | Network on-call | DRG, RPC, load balancer, steering |
| Network operations recovery team | **Network** | Network on-call | RB-02 §4, `steer-traffic.sh` |
| Application recovery team(s) | **EBS functional** | EBS functional lead | RB-02 §6, validation pack |
| Test team | folded into **EBS functional** | EBS functional lead | Validation is the functional team's signature ([`docs/10`](../docs/10-phase-reconstitution.md) §3.1) |
| Telecommunications team | **Not applicable** | — | No owned circuits; connectivity is OCI backbone (`docs/01` §1, A6) |
| Transportation and relocation team | **Not applicable** | — | No physical relocation ([`docs/08`](../docs/08-phase-activation-notification.md) §4) |
| Physical / personnel security team | **Not applicable** at system level | — | Oracle's responsibility for the regions; organization's for offices |
| Procurement team | **Not staffed** | — | Escalation to the OCI account team POC instead ([`contact-roster.md`](contact-roster.md) §5) |
| Media relations team | **Out of scope** | — | Organization-wide function; escalation destination only (§5) |
| Legal affairs team | **Out of scope** | — | Same |

### 3.1 Every team leader has a named alternate

> "Team leaders should have a designated alternate to act as the leader if the primary leader
> is unavailable."
> — §3.4.6, printed page 26 [1]

| Team | Leader | Alternate | Second alternate |
|---|---|---|---|
| Command | `{name}` | `{name}` | `{name}` |
| Assessment | `{name}` | `{name}` | `{name}` |
| Database | `{name}` | `{name}` | `{name}` |
| Application tier | `{name}` | `{name}` | `{name}` |
| Network | `{name}` | `{name}` | `{name}` |
| EBS functional | `{name}` | `{name}` | `{name}` |

**A team with one name in it is not a team.** NIST: "Teams should be sufficient in size to
remain viable if some members are unavailable to respond" (§3.4.6, printed page 26) [1]. Any
row above where the leader and both alternates resolve to the same person, or where the
alternates cannot actually perform the work, is a single point of failure in the plan — and
it will be found during the drill, not before it. Record it in the risk register rather than
leaving the cell optimistic.

### 3.2 The disruption may take the people too

> "The ISCP Coordinator should also consider that a disruption could render some personnel
> unavailable to respond. In this situation, executing the plan may be possible only by using
> personnel from another geographic area of the organization or by hiring contractors or
> vendors."
> — §3.4.6, printed page 26 [1]

Two cases this environment should have an answer for, both currently unanswered:

- **Geographic concentration.** If the recovery teams sit in one office or one time zone, an
  event affecting that location affects the plan as well as the environment.
- **Vendor fallback.** Whether Oracle Advanced Customer Support or a partner can execute any
  part of the recovery, and under what contract.

Both are marked `{to be resolved}` below rather than assumed.

| Question | Answer |
|---|---|
| Primary location of the recovery teams | `{to be resolved}` |
| Out-of-region personnel who can execute RB-02 | `{to be resolved}` |
| Contracted vendor fallback and its SLA | `{to be resolved}` |

---

## 4. Responsibilities by phase

Rows are teams; columns are the three phases in
[`docs/08`](../docs/08-phase-activation-notification.md),
[`docs/09`](../docs/09-phase-recovery.md) and
[`docs/10`](../docs/10-phase-reconstitution.md). **L** = leads, **S** = supports, **I** =
informed.

| Team | 1. Activation and Notification | 2. Recovery | 3. Reconstitution |
|---|---|---|---|
| **DR Commander** | **L** — declares or does not declare (RB-02 §0) | I — receives escalations at the §5 thresholds | **L** — announces deactivation ([`docs/10`](../docs/10-phase-reconstitution.md) §4.2) |
| **Command / DR Coordinator** | S — runs the gate, starts the call tree | **L** — owns the sequence and all escalations | **L** — owns the exit checklist ([`docs/10`](../docs/10-phase-reconstitution.md) §5) |
| **Assessment** | **L** — produces the repair estimate | S — feeds revised estimates into escalation | S — contributes to the after-action record |
| **Database** | S — Data Guard state to the assessment | **L** — role transition, gap and SCN evidence | **L** — re-protection: new standby, fresh backup |
| **Application tier** | I | **L** — storage activation, compute, EBS bring-up | S — drift reconciliation, cleanup |
| **Network** | S — connectivity signal to the assessment | **L** — steering and load balancer | S — retires temporary answers |
| **EBS functional** | I | **L** — Work Recovery Time activities (RB-02 §6) | **L** — signs the validation pack |
| **Business owner** | S — consulted if reachable in 15 min | **L** — RPO-breach decision (RB-02 §7d) | **L** — accepts service restoration |
| **Finance / CFO delegate** | S — period-close judgment | **L** — clears Concurrent Managers after an RPO breach | I |
| **Risk / audit** | I | I | S — receives evidence; owns the plan-change route |

---

## 5. Escalation destinations outside this plan

The plan escalates *out* in four directions. Each needs a named destination before an
incident, because none of them are reachable through the technical call tree.

| Trigger | Destination | Named |
|---|---|---|
| Recovery overruns the [`docs/09`](../docs/09-phase-recovery.md) §5 thresholds | DR Commander, then CIO | `{name}` |
| Data loss exceeds the tier RPO (RB-02 §7d) | Business owner + CFO delegate | `{name}` |
| Capacity or platform blocker (OCPU scaling refused, shape unavailable) | OCI account team / Oracle Support Sev 1 | [`contact-roster.md`](contact-roster.md) §5 |
| Suspected cyber cause, regulatory exposure, or media interest | Security incident response, Legal, Communications | `{name}` |

**The fourth row is the one to fill in before you need it.** A ransomware-driven recovery is
not only a continuity event, and the plan has no authority over the disclosure clock.

---

## 6. Maintenance

- Reviewed with [`contact-roster.md`](contact-roster.md), at the same cadence and by the same
  owner — a roster and a role list that disagree are worse than either alone.
- Re-verified after any reorganisation, any change of on-call vendor, and any departure of a
  named individual.
- Every `{name}`, `{to be resolved}` and empty alternate cell is an open gap. Count them at
  review time and report the count; a partially-filled roles table reads as complete at a
  glance and is not.

Signed: Business owner __________  CIO __________  Risk __________  Date __________

---

## References

This document is a synthesis: every statement about product behavior or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *NIST Special Publication 800-34 Rev. 1, Contingency Planning Guide for Federal
   Information Systems.* National Institute of Standards and Technology, May 2010 (errata
   2010-11-11), accessed 2026-09-02.
   <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf> —
   Supports: §4.1, printed page 35 (PDF page 49): "The roles and responsibilities section
   presents the overall structure of contingency teams, including the hierarchy and
   coordination mechanisms and requirements among the teams" (introduction); footnote 31,
   printed page 36 (PDF page 50): "The designated authority (typically a senior manager or
   CIO) has the authority to activate the contingency plan. … Only one individual should have
   this authority, and a successor should be clearly identified to assume that responsibility
   if necessary" (§1, §2); §3.4.6, printed page 26 (PDF page 40): "In addition to a single
   authoritative role for overall decision-making responsibility, including plan activation, a
   capable strategy will require some or all of the following groups", the fifteen-team list
   from "Management team (including the ISCP Coordinator)" to "Procurement team (equipment and
   supplies)", "The size of each team, team titles, and hierarchy designs depend on the
   organization", "Teams should be sufficient in size to remain viable if some members are
   unavailable to respond or alternate team members may be designated", "Team leaders should
   have a designated alternate to act as the leader if the primary leader is unavailable", and
   "The ISCP Coordinator should also consider that a disruption could render some personnel
   unavailable to respond. In this situation, executing the plan may be possible only by using
   personnel from another geographic area of the organization or by hiring contractors or
   vendors" (§3, §3.1, §3.2); Appendix A.2 Sample ISCP Template (Moderate Impact System) §2.3,
   printed page A.2-6 (PDF page 92): "At a minimum, a role should be established for a system
   owner or business unit point of contact, a recovery coordinator, and a technical recovery
   point of contact", and "Leadership roles should include an ISCP Director, who has overall
   management responsibility for the plan, and an ISCP Coordinator, who is responsible to
   oversee recovery and reconstitution progress, initiate any needed escalations or awareness
   communications, and establish coordination with other recovery and reconstitution teams as
   appropriate" (introduction, §1).

### Unverified statements

- Separating the DR Commander (declares) from the DR Coordinator (recovers) is this plan's
  engineering judgment. NIST names an ISCP Director and an ISCP Coordinator and does not
  state whether one individual may hold both.
- The succession intervals in §2 (10 minutes, then 15) are this plan's own figures, chosen to
  fit inside the ten-minute decision gate in `RB-02` §0. No source read in this revision
  specifies succession intervals.
- The team consolidations in §3 — folding the OS administration team into Application tier,
  the LAN/WAN team into Network, and the test team into EBS functional — are this plan's
  tailoring of NIST's candidate list to an environment of roughly five application nodes. NIST
  permits tailoring and does not prescribe these particular merges.
- The "not applicable" verdicts for the telecommunications, transportation and relocation, and
  physical security teams follow from the cloud-hosted scope stated in `docs/01` §1, not from
  any statement in NIST.

[1]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf "NIST SP 800-34 Rev. 1"
