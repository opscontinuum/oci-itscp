# Contingency Training

Training is the one of NIST's three TT&E activities that this plan did not evidence. NIST SP
800-34 Rev. 1 §3.5 treats **testing** (§3.5.1), **training** (§3.5.2) and **exercises** (§3.5.3)
as distinct activities and lists them on separate rows of its TT&E activity table [1].
`runbooks/RB-04-dr-drill.md` is the exercise and test programme. This checklist is the training
programme: who must be trained, on what, by when, and what record proves it.

The requirement, quoted as printed (the doubled "that that" is NIST's) [1]:

> Training should be provided at least annually. Personnel newly appointed to ISCP roles should
> receive training shortly thereafter. Ultimately, ISCP personnel should be trained to the extent
> that that they are able to execute their respective recovery roles and responsibilities without
> aid of the actual ISCP document.

NIST gives the reason in the next sentence: the plan may be unavailable "for the first few hours,
as a result of the disruption" [1]. That is the standard this checklist evidences — not that a
person can follow a runbook, but that they can act for the first few hours without one.

## 1. Why the drill programme does not evidence this on its own

`docs/07-itil4-alignment.md` §1a maps RB-04 to NIST SP 800-53 CP-4 and, until this checklist
existed, also claimed CP-3 on the strength of RB-04 §4's "primary DBA unavailable" inject. Three
things in the documents themselves show why that was not enough:

| Requirement [1][2] | What RB-04 actually provides | Gap |
|---|---|---|
| Per-person, at least annually | Quarterly drills, but RB-04 §5's evidence list (timing sheet, scenario results, plan log, lag, defects, attestation) records no attendance and no per-person outcome | No record exists that any named role holder was trained in any given year |
| "Shortly thereafter" for new appointees; CP-3 a.1 "within [organization-defined time period] of assuming a contingency role" | Nothing in RB-04 is triggered by an appointment | A new DBA on-call can hold the role for a full drill cycle untrained |
| Execute the role "without aid of the actual ISCP document" | RB-04 §4's inject "tests whether the runbook works without the expert" — the opposite direction — and runs only from the third drill onward, as one of five rotating injects | The drill evidences that the *plan* survives losing a person, not that a *person* survives losing the plan |

SP 800-53 Rev. 5 does allow that "at the discretion of the organization, participation in a
contingency plan test or exercise, including lessons learned sessions subsequent to the test or
exercise, may satisfy contingency plan training requirements" [2]. This plan exercises that
discretion narrowly, in §5: drill participation counts toward the **annual refresher** for a
person who performed their own role in the drill and attended the lessons-learned session. It
never satisfies the new-joiner requirement (§4) or the closed-book standard (§6), because a drill
is run with the runbook open, and should be.

## 2. Roles in scope

Every role named in `checklists/dr-authority-matrix.md` (the authority table, the standing
decisions and the contact roster), plus the one drill-isolation owner RB-04 names that the matrix
does not. Primaries **and deputies** are in scope: a deputy who has never been trained is not a
deputy.

| Role | Where the role is defined | Training tier (§3) |
|---|---|---|
| DR Commander; Deputy DR Commander | Authority matrix: declares disaster, invokes RB-02 without CAB | Decision |
| DR Coordinator | Authority matrix: RB-01, RB-03, RB-04 Level 2, HOT → WARM | Decision + Technical |
| Infra Manager | Authority matrix: deputy for Level 2 and HOT → WARM; co-signs replication deletion | Decision |
| DBA on-call | Authority matrix, contact roster; RB-02 §1, §3, §8; RB-04 §2 | Technical |
| Windows / infra on-call ("Infra on-call" in the authority table) | Authority matrix, contact roster; RB-02 §4–§5; RB-05 §1 | Technical |
| Network on-call | Contact roster; RB-02 §2 (traffic steering); RB-04 §Isolation | Technical |
| EBS functional lead | Authority matrix, contact roster; RB-02 §6; RB-04 §Isolation | Technical + Business |
| Integrations lead | RB-04 §Isolation (SOA / ISG endpoint isolation) — not in the authority matrix | Technical |
| Finance representative | Contact roster; RB-02 §6–§7d; drill timing sheet W5 | Business |
| Business owner | Authority matrix, contact roster; RB-04 §5 attestation | Decision + Business |
| CFO or delegate | Authority matrix: period-close and RPO-breach decisions | Decision + Business |
| Risk | Authority matrix: co-signs replication deletion; evidence retention | Decision |
| FinOps | Authority matrix: notified on WARM → HOT | Awareness only (module T1) |

## 3. Annual syllabus

Modules follow the six plan elements NIST says recovery personnel should be trained on:
purpose of the plan; cross-team coordination and communication; reporting procedures; security
requirements; team-specific processes; and individual responsibilities, the last two across the
Activation and Notification, Recovery, and Reconstitution phases [1]. NIST's own sample activities
for CP-3 are "a seminar and/or briefing" and role instruction "includ[ing] refresher training",
with simulated events incorporated for a high-impact system [1]; CP-3(1) says the same [2].

| Module | NIST plan element [1] | Content | Source material | Format |
|---|---|---|---|---|
| **T1** Purpose, scope and tiers | Purpose of the plan | The two-AD-plus-one-region design and why the likely and catastrophic failures are separated; the four MTD tiers and that MTD = RTO + WRT is this plan's decomposition; the four postures and the rule that tear-down never touches replication | `README.md`, `docs/02-mtd-tiers.md` §1–§2, `runbooks/RB-05-replication-lifecycle.md` §1 | Briefing, 60 min |
| **T2** Roles, authority and the decision gate | Individual responsibilities — Activation and Notification | The authority table row by row; the five standing decisions; the RB-02 §0 gate and why declaring late burns MTD margin; the two decisions that stop a failover (RPO breach, period close) | `checklists/dr-authority-matrix.md`, `runbooks/RB-02-failover.md` §0 | Briefing, 60 min |
| **T3** Coordination, communication and reporting | Cross-team coordination and communication; Reporting procedures | How a disaster is declared and by whom; the bridge and channels; what the data-loss statement is, who produces it and who receives it; what is escalated to the business (an MTD breach is escalated "immediately — do not absorb it silently", RB-02 §7b); what lands in `evidence/` and why | `runbooks/RB-02-failover.md` §1, §6, §7b, §8; `evidence/README.md` | Briefing, 45 min |
| **T4** Security requirements during recovery and drills | Security requirements | The one-way-door catalogue and the `--confirm` guard; the drill isolation controls and why a drill that transmits a real payment file is worse than no drill; `evidence/` sensitivity and retention; credentials and the Oracle Support severity-1 path | `docs/03-replication-matrix.md` §2, `runbooks/RB-04-dr-drill.md` §Isolation, `evidence/README.md` | Briefing, 45 min |
| **T5** Team-specific processes | Team-specific processes — Recovery and Reconstitution | Role-specific walk-through of RB-02 (failover), RB-01 (switchover), RB-03 (failback), RB-04 (drill), RB-05 (lifecycle), taken with the documents open, ending with the role's closed-book card from §6 | The runbooks, `checklists/pre-failover-precheck.md`, `checklists/drill-timing-sheet.md` | Instruction, 90–120 min per tier |
| **T6** Simulated event | Individual responsibilities — Recovery and Reconstitution; CP-3(1) simulated events [2] | A scripted scenario (regional loss during period close; AD-1 loss with FSFO promotion; drill in progress when an incident hits) talked through by the trainee **from memory** with the assessor scoring the §6 card. This is the closed-book check, not a tabletop exercise: one person, one role, no equipment | §6 role cards | Assessed walk-through, 30 min |

**Who takes what.** Decision tier: T1–T4, T5 (decision walk-through), T6. Technical tier:
T1–T6 with T5 in full for the role's runbook sections. Business tier: T1–T3, T5 (WRT and
sign-off sections), T6. Awareness: T1 only.

**Cadence — this plan's organisation-defined values.** NIST SP 800-34 says "at least annually"
[1]; SP 800-53 CP-3 a.3 leaves the frequency to the organisation [2]. This plan sets:

- every role holder, primary and deputy: T1–T6 for their tier **within 12 months** of their last
  completion, and never later than 12 months after appointment;
- **additionally after a material plan change** (CP-3 a.2 "when required by system changes" [2]):
  a delta briefing on the changed section, recorded in the register, within 30 days of the
  change being merged — a new one-way door, a changed decision-gate threshold, a new posture, or a
  role change in the authority matrix all qualify;
- **syllabus content review** (CP-3 b [2]): annually, after every drill's lessons-learned session,
  after any invocation of RB-01/RB-02/RB-03, and on any audit finding. SP 800-34 §3.6 lists
  "training and awareness materials" among the elements a plan review must cover [1].

## 4. New-joiner path — "shortly thereafter"

**Trigger.** A person is appointed as primary or deputy to any role in §2, including joining the
DBA, Windows/infra or network on-call rota. The appointment date is the date the authority matrix
or contact roster is changed, or the date they first appear on the rota, whichever is earlier.

**Deadline — this plan's organisation-defined period for CP-3 a.1 [2].** Complete the path
**within 30 calendar days of appointment, and before the first on-call shift or first sole
holding of the role, whichever comes first.** Until then the person is *in training*: they may
shadow, but a trained primary or deputy must remain reachable for the role. A new DBA on-call
appointed the day after a quarterly drill would otherwise wait up to three months for the next
one, which is the case the issue this checklist closes was raised for.

| Day | Step | Owner | Record |
|---|---|---|---|
| 0 | Appointment recorded; register row opened (§7) | DR Coordinator | Register |
| ≤ 7 | T1 + T2 (briefing; may be a recording plus a 20-minute Q&A with the DR Coordinator) | DR Coordinator | Register |
| ≤ 14 | T3 + T4 | DR Coordinator, with the Risk function for the evidence-sensitivity part of T4 | Register |
| ≤ 21 | T5 for the role, delivered by the current primary holder of that role | Current primary | Register |
| ≤ 30 | T6 closed-book walk-through, assessed by a *different* trained holder of the same or a senior role (never the person who delivered T5) | Assessor | Register + card |
| next scheduled drill | Participates in RB-04 in their role — as the second person in that role, not the only one, for their first drill | DR Coordinator | Drill evidence (RB-04 §5) |

The drill is the last step, not a substitute for the others. NIST's definition of training is
what prepares personnel "for participation in exercises, tests, and actual emergency situations",
and it describes role training before an exercise as "a presentation on their roles and
responsibilities and activities that allow personnel to demonstrate their understanding" [1] —
that presentation is T1–T5 and that demonstration is T6.

## 5. When drill participation counts

Under SP 800-53 CP-3's discretion clause [2], this plan counts a person's RB-04 participation as
their **annual refresher (T5 + T6)** only when all of the following are recorded in that drill's
`evidence/drill-YYYY-MM-DD/` folder and copied to the register:

- [ ] the person performed **their own role** in the drill (an observer or a stand-in for another
      role does not count);
- [ ] the drill was Level 2 or Level 3 — Level 1 is a component test and exercises no recovery role;
- [ ] the person attended the **lessons-learned session** and the defect list names them where
      relevant;
- [ ] the drill lead confirms in the register that the person executed the role's first-hour actions
      **before opening the runbook** — if the drill lead cannot say so, the §6 closed-book check is
      still due.

T1–T4 are refreshed by briefing regardless. Drill participation never discharges the new-joiner
path (§4).

## 6. Evidencing "without aid of the actual ISCP document"

The closed-book walk-through (T6) is scored on a role card. The assessor reads the scenario, the
trainee answers with no document, screen or note open, and the assessor ticks each item as
**unprompted**, **prompted** or **missed**. Pass is every item unprompted; one prompted item is a
pass with a re-check at the next quarterly drill; any missed item, or two prompted, is a fail and
a repeat within 14 days. The card, scored and signed by both, is filed with the register (§7).

The cards below list the items each role must produce from memory. They are the actions a person
would need in the first few hours if every copy of this repository were unreachable; everything
else can wait for the document. Item wording is deliberately the runbook's own, so the card stays
correct only if it is re-checked when the runbook changes (§3, content review).

**DR Commander and Deputy** (`RB-02` §0–§1, authority matrix)
1. The RB-02 §0 gate, in order: is `EBSPROD_IAD` reachable and openable → is a drill in progress
   (Stop Drill first; Switchover and Failover are refused while one is active) → did FSFO already
   promote `EBSPROD_IAD2` in Ashburn, and is the AD-2 app tier serving → is the whole region or the
   ExaDB-D infrastructure lost → is estimated repair time greater than MTD minus time elapsed
   minus the ~60-minute failover RTO.
2. They declare without CAB; the business owner is consulted if reachable within 15 minutes; the
   Tier-0 MTD is 2 hours and declaring late burns the margin.
3. The two decisions that are not theirs: data loss beyond tier RPO (business owner plus CFO
   delegate) and failover during period close (CFO or delegate).
4. Their first instruction to the DBA: capture forensics before promoting anything.
5. How to open the bridge and reach the DBA on-call and the business owner without consulting
   the roster document.

**DR Coordinator** (authority matrix; `RB-01`, `RB-03`, `RB-04`, `RB-05` §1)
1. Which actions need CAB (RB-01 switchover, RB-03 failback) and which do not (Level 2 drill,
   HOT → WARM).
2. The four postures, that WARM is the steady state, and that no posture change ever stops
   replication.
3. Before a Level 2 drill: FRA headroom for the guaranteed restore point, the drill-only DNS
   resolution view, and the signed manual isolation sheet with a named owner per check.
4. The drill clock stops at Finance sign-off, not at login, and measured numbers go back into
   `docs/02`.

**Infra Manager** (authority matrix)
1. Deputy authority for Level 2 and HOT → WARM.
2. Deleting replication needs written sign-off from Infra Manager *and* Risk, because re-enabling
   forces a full baseline and a multi-hour unprotected window.
3. Scaling ExaDB-D below the OCPU floor is refused by tooling and scaling to zero stops redo apply.

**DBA on-call** (`RB-02` §1, §3, §8; `RB-04` §2; `RB-03` §2)
1. First: run the lag snapshot and replication-state capture — the transport lag at that moment
   is the data-loss bound, not the apply lag.
2. `disable fast_start failover force` **before** `failover to EBSPROD_PHX`, and why: a manual
   failover can only go to the current FSFO target, which is `EBSPROD_IAD2`, not Phoenix.
3. Reinstating `EBSPROD_IAD` afterwards needs Flashback Database to have been on beforehand;
   otherwise it is a full `RMAN DUPLICATE ... FOR STANDBY FROM ACTIVE DATABASE`.
4. After service is declared: enable Autonomous Recovery Service on `EBSPROD_PHX`, because only
   one region's database is protected at a time and nothing is backing up the new primary until
   then.
5. Drill conversions go through `oci db database convert-standby-database-type`, not raw DGMGRL,
   so Full Stack DR and the Data Guard Group see the role change; a drill needs an FRA, not
   Flashback.
6. If RPO is breached, Concurrent Managers stay down until Finance clears them.

**Windows / infra on-call** (`RB-02` §2, §4–§5, §8; `RB-05` §1)
1. The three storage activations — volume group replica, FSS replication, Object Storage policy —
   are one-way doors; each script refuses without `--confirm` and writes to the storage-failover
   log.
2. App-tier bring-up order: storage attached and `fs1`/`fs2`/`fs_ne` present → `cmclean.sql` with
   all managers down → EBS services → Concurrent Managers last → verify `FND_NODES` against the
   logical hostnames.
3. `Start-EBSAppTier.ps1 -DrillMode` aborts if the mailer or site-banner check fails; drill
   instances use distinct physical names but the same logical names.
4. Immediately after service is declared: start reverse replication for every storage tier, and
   bulk-copy the bucket before creating the reverse Object Storage policy.

**Network on-call** (`RB-02` §2; `RB-04` §Isolation; `docs/01` §5.1)
1. Traffic steering to Phoenix is the last step of the failover sequence, and the manual override
   path when steering fails to propagate (an RB-04 §4 inject).
2. Logical hostnames are identical across regions and resolved region-locally; a drill needs the
   drill-only resolution view or EBS fails the `FND_NODES` check.
3. The drill load balancer stays on a private listener and is never registered in Traffic
   Management.

**EBS functional lead** (`RB-02` §5–§7; `RB-04` §Isolation)
1. The six WRT activities of RB-02 §6 and that they start in parallel with app-tier bring-up.
2. Concurrent Managers are started by this role, last, and not at all after an RPO breach until
   Finance clears them.
3. The drill isolation checks this role owns: outbound trading-partner and payment endpoints
   redirected to sinks; Oracle Alert e-mail and BI Publisher delivery disabled or redirected —
   `wfmlpcln.sql` covers only the Workflow mailer.
4. An open `adop` cycle is fixed after service is restored, not during the outage.

**Integrations lead** (`RB-04` §Isolation; `RB-02` §6)
1. SOA / ISG endpoints must be isolated before a drill's managers start; a drill that reaches a
   live partner endpoint is a real transmission.
2. The interface-replay path: inbound files from the replicated bucket for the window between the
   last replica and the incident; outbound files re-transmitted from the ledger.

**Finance representative** (`RB-02` §1, §6, §7d; drill timing sheet)
1. Their sign-off (W5) ends the WRT clock and therefore the MTD clock — for drills and for real.
2. What the data-loss statement is and that it exists before anything is promoted.
3. RPO breach means Finance convenes before any batch processing runs.
4. The reconciliation report pack is a precondition of sign-off.

**Business owner** (authority matrix; `RB-04` §5)
1. Consulted on declaration if reachable within 15 minutes; the declaration does not wait.
2. Joint authority with the CFO delegate to proceed when data loss exceeds tier RPO; approval
   required for RB-03 failback and the second outage window it needs.
3. Signs the drill attestation and, with Risk, any decommission.

**CFO or delegate** (authority matrix; `RB-02` §7d)
1. Failover during period close is their call alone.
2. Proceeding past an RPO breach needs them and the business owner, and the consultation is
   mandatory, not advisory.

**Risk** (authority matrix; `evidence/README.md`; `RB-05` §5)
1. Co-signs replication deletion in writing.
2. `evidence/` is archived before any decommission and falls under the SOX-relevant retention
   schedule.

## 7. Training register

Kept in `evidence/training-register.md`, one row per completion, append-only; the scored T6
cards go in `evidence/training-YYYY-MM-DD/<role>.md`. This is personal data about named people
and inherits the handling decision in `evidence/README.md` — in this example repository it is
not populated.

| Name | Role (primary / deputy) | Appointed | T1–T4 completed | T5 completed (by) | T6 result (date, assessor) | Basis (path §4 / refresher §3 / drill §5) | Next due |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

**Roster completeness — checked at every quarterly drill and on every authority-matrix change.**
For each role in §2:

- [ ] the current primary has a T6 pass dated within the last 12 months;
- [ ] at least one deputy has a T6 pass dated within the last 12 months;
- [ ] nobody appointed more than 30 days ago is still *in training*;
- [ ] every material plan change since the last check has a delta-briefing row for every affected
      role holder.

A failed check is a defect on the drill's defect list with the DR Coordinator as owner, whether
or not a drill is running.

---

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *Contingency Planning Guide for Federal Information Systems.* NIST Special Publication 800-34
   Rev. 1, May 2010 (errata 2010-11-11), accessed 2026-09-02.
   <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf> — Supports:
   §3.5 separates testing (§3.5.1), training (§3.5.2) and exercises (§3.5.3) (intro); §3.5.2,
   p. 28: "Training should be provided at least annually. Personnel newly appointed to ISCP
   roles should receive training shortly thereafter. Ultimately, ISCP personnel should be trained
   to the extent that that they are able to execute their respective recovery roles and
   responsibilities without aid of the actual ISCP document," the "first few hours" rationale,
   and the six plan elements recovery personnel should be trained on (intro, §3); the p. 29
   sidebar defining training as preparing personnel "for participation in exercises, tests, and
   actual emergency situations" and describing it as "a presentation on their roles and
   responsibilities and activities that allow personnel to demonstrate their understanding" (§4);
   the ISCP TT&E activity table, p. 30 — captioned "Table 3-6" in the body but listed as
   "Table 3-5" in the document's own list of tables — whose CP-3 rows are "a seminar and/or
   briefing" and role instruction that "includes refresher training. (For a high-impact system,
   incorporate simulated events.)" (intro, §3); §3.6, p. 33, listing "training and awareness
   materials" among plan-review elements (§3).
2. *Security and Privacy Controls for Information Systems and Organizations.* NIST Special
   Publication 800-53 Rev. 5 (Update 1), September 2020 with updates through 2020-12-10,
   accessed 2026-09-02.
   <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf> — Supports:
   CP-3 a.1 "Within [Assignment: organization-defined time period] of assuming a contingency role
   or responsibility"; a.2 "When required by system changes"; a.3 "[Assignment:
   organization-defined frequency] thereafter"; b "Review and update contingency training content
   [Assignment: organization-defined frequency] and following [Assignment: organization-defined
   events]" (§1, §3, §4); the Discussion sentence "At the discretion of the organization,
   participation in a contingency plan test or exercise, including lessons learned sessions
   subsequent to the test or exercise, may satisfy contingency plan training requirements"
   (§1, §5); CP-3(1) "Incorporate simulated events into contingency training to facilitate
   effective response by personnel in crisis situations" (§3) — all on pp. 118–119.

### Unverified statements

- §3, §4: the 12-month refresher, 30-day new-joiner deadline, 30-day delta-briefing window and
  14-day re-test are this plan's own organisation-defined values for the assignments NIST leaves
  open; no source prescribes them.
- §6: the pass/prompted/missed scoring and the role-card item lists are engineering judgement
  about what a role holder needs in the first few hours, derived from the runbooks cited on each
  card, not from a NIST or Oracle source.

[1]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf "NIST SP 800-34 Rev. 1 — Contingency Planning Guide for Federal Information Systems"
[2]: https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf "NIST SP 800-53 Rev. 5 — Security and Privacy Controls for Information Systems and Organizations"
