# 09 — Phase 2: Recovery

**The phase that restores service.** It begins the moment the disaster is declared and ends
when EBS is serving users from `us-phoenix-1` — functional, but not yet proven, and not yet
back to normal operations. Proving it is [`docs/10`](10-phase-reconstitution.md).

This is the second of the three phases NIST SP 800-34 Rev. 1 requires an ISCP to describe in
its concept of operations (§4.1, printed page 35) [1]. See
[`docs/08`](08-phase-activation-notification.md) for the phase map as a whole.

> ### These documents route; they do not instruct
>
> Every procedural step lives in a runbook or a script. If you are executing, go to the file
> named in the routing table.

---

## 1. What NIST means by this phase

> "Formal recovery operations begin after the ISCP has been activated, outage assessments
> have been completed (if possible), personnel have been notified, and appropriate teams have
> been mobilized. Recovery Phase activities focus on implementing recovery strategies to
> restore system capabilities, repair damage, and resume operational capabilities at the
> original or new alternate location. At the completion of the Recovery Phase, the
> information system will be functional and capable of performing the functions identified in
> the plan."
> — §4.3, printed page 39 [1]

Note the two hedges NIST builds in, both of which this plan relies on. "**(if possible)**"
— assessment may be impossible when the primary region is simply gone, and RB-02 §0's
*declared* branch does not require a completed assessment. And "**the functions identified in
the plan**" — not all functions. NIST is explicit: "It is feasible that only system resources
identified as high priority in the BIA will be recovered at this stage" (§4.3, printed page
39) [1]. Here, that is Tier 0 (`docs/02` §3).

Three activities: **sequence of recovery activities** (§4.3.1), **recovery procedures**
(§4.3.2), **recovery escalation and notification** (§4.3.3).

---

## 2. Entry and exit

| | Condition | Where it is defined |
|---|---|---|
| **Entry** | Disaster declared by the authority in `roles-and-responsibilities.md` §2, per the gate. | [`RB-02`](../runbooks/RB-02-failover.md) §0 |
| **Exit** | Tier 0 functions are being served from Phoenix and the service is declared available to users. The system is *functional*, not *validated* — validation is Reconstitution. | [`RB-02`](../runbooks/RB-02-failover.md) §8 |

**Two different runbooks reach this phase.** Which one you are in was decided before the
phase began, and they are not interchangeable:

| Path | Runbook | When | Data loss |
|---|---|---|---|
| **Planned** — the primary is healthy and reachable | [`RB-01-switchover.md`](../runbooks/RB-01-switchover.md) | Announced threat window, region maintenance, a rehearsed migration | None. Oracle Data Guard switchover is a role transition, not a failover |
| **Unplanned** — the primary is lost or unreachable | [`RB-02-failover.md`](../runbooks/RB-02-failover.md) | Regional disaster, unrecoverable corruption, declared per RB-02 §0 | Up to the cross-region transport lag; attested per [`docs/04`](04-monitoring.md) §4 |

Everything below applies to both unless the row says otherwise.

---

## 3. Sequence of recovery activities (§4.3.1)

> "The sequence of activities should reflect the system's MTD to avoid significant impacts to
> related systems. Procedures should be written in a stepwise, sequential format so system
> components may be restored in a logical manner."
> — §4.3.1, printed page 39 [1]

The sequence is fixed by dependency, not by preference, and both runbooks execute it in the
same order:

| # | Step | Why it is in this position | File |
|---|---|---|---|
| 1 | Quiesce the application tier — **Concurrent Managers first** | An in-flight concurrent request writing during a role transition is the hardest class of damage to reason about afterwards. Stopping the writers precedes stopping the readers. | [`RB-01`](../runbooks/RB-01-switchover.md) §3; [`RB-02`](../runbooks/RB-02-failover.md) §2 |
| 2 | Capture forensics (unplanned only) | Evidence is destroyed by recovery. Five minutes, parallelisable, and unrecoverable if skipped. | [`RB-02`](../runbooks/RB-02-failover.md) §1 |
| 3 | Transition the database | Everything downstream needs a writable database with a known SCN. | [`RB-01`](../runbooks/RB-01-switchover.md) §3; [`RB-02`](../runbooks/RB-02-failover.md) §3 |
| 4 | Activate storage — block, then file, then object | The application tier mounts these. Activating a Volume Group replica takes its **last synced point**; activating before the replica has caught up silently strands writes. | [`RB-02`](../runbooks/RB-02-failover.md) §4; [`scripts/oci/storage-failover-lib.sh`](../scripts/oci/storage-failover-lib.sh) |
| 5 | Scale the standby Exadata off its OCPU floor | Redo apply at the floor is not the same workload as serving production. | [`scripts/oci/scale-exadata-ocpu.sh`](../scripts/oci/scale-exadata-ocpu.sh); floor rationale in [`docs/02`](02-mtd-tiers.md) §4 |
| 6 | Start compute, then EBS | Logical host names resolve region-locally; this is the step the whole naming design in [`docs/01`](01-architecture.md) §5.1 exists to make cheap. | [`RB-02`](../runbooks/RB-02-failover.md) §5; [`scripts/windows/Start-EBSAppTier.ps1`](../scripts/windows/Start-EBSAppTier.ps1) |
| 7 | Steer traffic | Last, so no user reaches a half-built stack. | [`scripts/oci/steer-traffic.sh`](../scripts/oci/steer-traffic.sh) |
| 8 | Work Recovery Time activities — **in parallel with 6–7** | WRT is not a tail appended to RTO; it is concurrent work that determines whether MTD is met. | [`RB-02`](../runbooks/RB-02-failover.md) §6; drivers in [`docs/02`](02-mtd-tiers.md) §6 |

**Step 8 is the one most plans get wrong.** NIST defines MTD as covering the whole
disruption, and states that reprocessing time "must be added to the RTO" (§3.2.1, printed
page 17) [1] — but adding it *serially* is a planning choice, not a requirement. This plan
starts interface replay and concurrent-request reconciliation while the app tier is still
coming up, because Tier 0's two-hour MTD does not survive a serial 30-minute WRT appended to
a 60-minute RTO plus a decision gate.

---

## 4. Recovery procedures (§4.3.2)

> "Recovery procedures should be written in a straightforward, step-by-step style. To prevent
> difficulty or confusion in an emergency, no procedural steps should be assumed or omitted."
> — §4.3.2, printed page 40 [1]

NIST does not supply procedures — "Given the extensive variety of system types,
configurations, and applications, this planning guide does not provide specific recovery
procedures" (§4.3.2, printed page 39) [1]. This plan's are the runbooks, and they are the
ISCP's Appendix D equivalent (§4.5, printed page 42: "Detailed recovery procedures and
checklists") [1].

Mapping NIST's list of typical recovery actions (§4.3.2, printed page 40) [1] to this estate:

| NIST action | Here |
|---|---|
| "Obtaining authorization to access damaged facilities" | Not applicable — no physical access. The equivalent is OCI IAM authority, held standing per [`dr-authority-matrix.md`](../checklists/dr-authority-matrix.md) |
| "Notifying internal and external business partners associated with the system" | [`contact-roster.md`](../checklists/contact-roster.md) §5; interface replay in [`RB-02`](../runbooks/RB-02-failover.md) §6 |
| "Obtaining necessary office supplies and work space" | Not applicable |
| "Obtaining and installing necessary hardware components" | Not applicable — Phoenix is pre-provisioned. This is the pilot-light design in [`docs/01`](01-architecture.md) §2 |
| "Obtaining and loading backup media" | Not applicable in the normal path — recovery is from a live Data Guard standby, not from backup. Backup restore is the Tier 3 path only ([`docs/02`](02-mtd-tiers.md) §2) |
| "Restoring critical operating system and application software" | Pre-installed on the Phoenix nodes; drift between regions is the risk, not absence. [`scripts/windows/Compare-NodeDrift.ps1`](../scripts/windows/Compare-NodeDrift.ps1), [`docs/04`](04-monitoring.md) §5 |
| "Restoring system data to a known state" | Data Guard failover; the known state is the SCN, and the gap is the transport lag |
| "Testing system functionality including security controls" | Deferred to Reconstitution — [`docs/10`](10-phase-reconstitution.md) §3 |
| "Connecting system to network or other external systems" | [`scripts/oci/steer-traffic.sh`](../scripts/oci/steer-traffic.sh); interconnections in [`contact-roster.md`](../checklists/contact-roster.md) §5 |
| "Operating alternate equipment successfully" | The exit condition in §2 |

### 4.1 Contingency branches are part of the procedure, not an appendix to it

RB-02 §7 carries four branches that are more likely than they look, and each is a place where
a recovery that was going fine stops going fine: an `adop` cycle open at the moment of
failure (§7a), a logical host name not preserved in the context file (§7b), a corrupt or
stale volume group replica (§7c), and data loss exceeding the Tier 0 RPO (§7d). §7d is not a
technical branch — it is a business decision that leaves the runbook and goes to the
authority in [`roles-and-responsibilities.md`](../checklists/roles-and-responsibilities.md)
§2.

---

## 5. Recovery escalation and notification (§4.3.3)

> "Effective escalation and notification procedures should define and describe the events,
> thresholds, or other types of triggers that are necessary for additional action."
> — §4.3.3, printed page 41 [1]

NIST names four trigger classes (§4.3.1, printed page 39) [1]. This plan's thresholds:

| NIST trigger | Threshold here | Action | Where |
|---|---|---|---|
| "An action is not completed within the expected time frame" | Any numbered step in §3 exceeds **twice** its drill-measured duration, or the elapsed total passes **50% of the tier MTD** | Escalate to the declaring authority; re-forecast against remaining MTD; consider the RB-02 §7 branches | [`roles-and-responsibilities.md`](../checklists/roles-and-responsibilities.md) §5 |
| "A key step has been completed" | Database transitioned (step 3); traffic steered (step 7); service declared (§8) | Status to the bridge and to the business owner, via the roster script | [`contact-roster.md`](../checklists/contact-roster.md) §4 |
| "Item(s) must be procured" | Standby capacity insufficient — OCPU scaling blocked, or Phoenix shape capacity unavailable | Escalate to the OCI account team POC | [`contact-roster.md`](../checklists/contact-roster.md) §5 |
| "Other system-specific concerns exist" | Measured data loss exceeds the tier RPO | RB-02 §7d — leaves the runbook, becomes a business decision | [`RB-02`](../runbooks/RB-02-failover.md) §7d |

*(Unverified: the specific thresholds — twice the drill-measured step duration, 50% of tier
MTD — are this plan's engineering judgement. NIST requires that thresholds be defined and
does not specify values.)*

---

## 6. If you are in this phase right now

1. Planned: [`RB-01-switchover.md`](../runbooks/RB-01-switchover.md), start at §1.
   Unplanned: [`RB-02-failover.md`](../runbooks/RB-02-failover.md), start at §1.
2. [`checklists/pre-failover-precheck.md`](../checklists/pre-failover-precheck.md) before the database step.
3. [`checklists/drill-timing-sheet.md`](../checklists/drill-timing-sheet.md) — time the steps even in a real event; this is where the next revision's MTD numbers come from.

Then go to [`docs/10-phase-reconstitution.md`](10-phase-reconstitution.md).

---

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *NIST Special Publication 800-34 Rev. 1, Contingency Planning Guide for Federal
   Information Systems.* National Institute of Standards and Technology, May 2010 (errata
   2010-11-11), accessed 2026-09-02.
   <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf> —
   Supports: §4.1, printed page 35 (PDF page 49): the three-phase structure (introduction);
   §4.3, printed page 39 (PDF page 53): "Formal recovery operations begin after the ISCP has
   been activated, outage assessments have been completed (if possible), personnel have been
   notified, and appropriate teams have been mobilized. … At the completion of the Recovery
   Phase, the information system will be functional and capable of performing the functions
   identified in the plan", and "It is feasible that only system resources identified as high
   priority in the BIA will be recovered at this stage" (§1); §4.3.1, printed page 39: "The
   sequence of activities should reflect the system's MTD to avoid significant impacts to
   related systems. Procedures should be written in a stepwise, sequential format so system
   components may be restored in a logical manner", and the escalation trigger list "An
   action is not completed within the expected time frame; A key step has been completed;
   Item(s) must be procured; and Other system-specific concerns exist" (§3, §5); §4.3.2,
   printed page 39: "Given the extensive variety of system types, configurations, and
   applications, this planning guide does not provide specific recovery procedures" (§4);
   §4.3.2, printed page 40 (PDF page 54): the typical recovery action list from "Obtaining
   authorization to access damaged facilities and/or geographic area" to "Operating alternate
   equipment successfully", and "Recovery procedures should be written in a straightforward,
   step-by-step style. To prevent difficulty or confusion in an emergency, no procedural
   steps should be assumed or omitted" (§4); §4.3.3, printed page 41 (PDF page 55):
   "Effective escalation and notification procedures should define and describe the events,
   thresholds, or other types of triggers that are necessary for additional action" (§5);
   §4.5, printed page 42 (PDF page 56): plan appendix list including "Detailed recovery
   procedures and checklists" (§4); §3.2.1, printed page 17 (PDF page 31): "that additional
   processing time must be added to the RTO" (§3).

### Unverified statements

- The escalation thresholds in §5 — twice the drill-measured step duration, and 50% of the
  tier MTD elapsed — are this plan's engineering judgement. NIST requires thresholds to be
  defined but specifies no values, and none have been calibrated against a completed Level 2
  drill in this revision.
- Running Work Recovery Time activities concurrently with application bring-up (§3, step 8)
  is this plan's design choice. NIST states that reprocessing time is added to the RTO; it
  does not address whether the work may overlap.
- The claim that an in-flight concurrent request is "the hardest class of damage to reason
  about afterwards" (§3, step 1) is engineering judgement; no documentation found in this
  revision.

[1]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf "NIST SP 800-34 Rev. 1"
