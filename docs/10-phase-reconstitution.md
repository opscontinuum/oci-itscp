# 10 — Phase 3: Reconstitution

**The phase everyone skips.** Service is back, the bridge is quiet, and the people who ran
the recovery want to sleep. Reconstitution is what separates *the system is up* from *the
system is proven, documented, and ready for the next outage* — and it is the phase whose
omission is discovered a year later, during the second disaster, when the plan turns out
never to have been updated after the first one.

This is the third of the three phases NIST SP 800-34 Rev. 1 requires an ISCP to describe in
its concept of operations (§4.1, printed page 35) [1]. See
[`docs/08`](08-phase-activation-notification.md) for the phase map as a whole.

---

## 1. What NIST means by this phase

> "The Reconstitution Phase is the third and final phase of ISCP implementation and defines
> the actions taken to test and validate system capability and functionality. During
> Reconstitution, recovery activities are completed and normal system operations are resumed.
> If the original facility is unrecoverable, the activities in this phase can also be applied
> to preparing a new permanent location to support system processing requirements. This phase
> consists of two major activities: validating successful recovery and deactivation of the
> plan."
> — §4.4, printed page 41 [1]

**Two activities, and this plan keeps them strictly separate.** Validation asks *is the
recovered system correct?* Deactivation asks *are we ready for the next one?* A recovery that
passes validation but skips deactivation leaves the estate unprotected — running in Phoenix
with no standby, no fresh backup, and no updated plan.

---

## 2. Entry and exit

| | Condition | Where it is defined |
|---|---|---|
| **Entry** | Tier 0 functions are being served from Phoenix; service declared available. | [`RB-02`](../runbooks/RB-02-failover.md) §8 |
| **Exit** | Validation complete, replication re-established in the new direction, a fresh backup taken, the after-action record written, and the plan formally deactivated. | §5 below |

> ### "Normal operations" does not mean "back in Ashburn"
>
> NIST's Reconstitution assumes a return to normal, and notes that if "the original facility
> is unrecoverable" the phase applies to establishing a new permanent location (§4.4, printed
> page 41) [1]. In this estate both are live options, and **they are different decisions
> taken at different times**:
>
> - **Reconstitute in place** — Phoenix becomes the permanent primary. Reconstitution ends here.
> - **Fail back to Ashburn** — a separate project, run later, under its own entry criteria.
>
> Failback is **not** part of this phase and must never be attempted as its tail.
> [`RB-03-failback.md`](../runbooks/RB-03-failback.md) §1 is titled "Why this is a project"
> for exactly this reason. Deactivating the plan does not require being back in Ashburn; it
> requires being *protected wherever you are*.

---

## 3. Validating successful recovery (§4.4)

NIST names three validation steps. All three exist here, but only two are performed.

| NIST step | Definition [1] | Status here | File |
|---|---|---|---|
| **Concurrent processing** | "the process of running a system at two separate locations concurrently until there is a level of assurance that the recovered system is operating correctly and securely" (§4.4, printed page 41) | **Not performed.** A single EBS instance with one authoritative database cannot run production in two regions at once; a second writable copy would diverge, and reconciling it is worse than the outage. NIST does not require it: "information systems are not required to have concurrent processing capabilities" (footnote 33, printed page 41) | Design basis in [`docs/01`](01-architecture.md) §1 (assumption A7) |
| **Validation data testing** | "the process of testing and validating recovered data to ensure that data files or databases have been recovered completely and are current to the last available backup" (§4.4, printed page 41) | **Performed.** Data Guard gap check, SCN/lag reconciliation, and the RPO attestation that records what was actually lost | [`RB-01`](../runbooks/RB-01-switchover.md) §5; [`docs/04`](04-monitoring.md) §4; [`scripts/oci/generate-rpo-attestation.sh`](../scripts/oci/generate-rpo-attestation.sh) |
| **Validation functionality testing** | "a process for verifying that all system functionality has been tested, and the system is ready to return to normal operations" (§4.4, printed page 41) | **Performed.** The validation pack — the functional team's list, not the DBA's | [`RB-01`](../runbooks/RB-01-switchover.md) §5; exit criteria in [`RB-03`](../runbooks/RB-03-failback.md) §5 |

### 3.1 Validation is the functional team's signature, not the infrastructure team's

The database opening read-write is not validation. The validation pack in RB-01 §5 exists
because the only person who can say *Order Management is correct* is someone who runs Order
Management. Infrastructure evidence — apply lag zero, all services up, load balancer healthy
— is a precondition for asking the question, not an answer to it.

**The RPO attestation is the honest half of this step.** Validation data testing asks whether
the data is current; in an unplanned failover the truthful answer is often *no, by N seconds
of transport lag*. `docs/04` §4 records that number rather than rounding it to zero, and
RB-02 §7d is what happens when it exceeds the tier RPO.

---

## 4. Deactivation of the plan (§4.4)

> "Deactivation of the plan is the process of returning the system to normal operations and
> finalizing reconstitution activities to prepare the system against another outage or
> disruption."
> — §4.4, printed page 41 [1]

NIST's five deactivation activities, mapped:

| NIST activity | What it means here | File |
|---|---|---|
| **Notifications** — "Upon return to normal operations, users should be notified by the ISCP Coordinator (or designee) using predefined notification procedures" (printed page 41) | Service-restored notice to users, the business owner, and every interconnected partner told during Activation | [`contact-roster.md`](../checklists/contact-roster.md) §4–§5 |
| **Cleanup** — "dismantling any temporary recovery locations, restocking supplies … and readying the system for another contingency event" (printed page 41) | Tear down drill-only resources, release activated volume-group clones, retire temporary DNS answers, return the posture to steady state | [`RB-05`](../runbooks/RB-05-replication-lifecycle.md) §3–§4; [`scripts/oci/set-dr-posture.sh`](../scripts/oci/set-dr-posture.sh) |
| **Offsite data storage** — return retrieved media (printed page 42) | **Not applicable.** No physical media. Backups are in Autonomous Recovery Service and Object Storage; nothing is retrieved or returned | [`docs/03`](03-replication-matrix.md) §1 |
| **Data backup** — "As soon as reasonable following reconstitution, the system should be fully backed up and a new copy of the current operational system stored for future recovery efforts" (printed page 42) | **The step most likely to be missed.** Ashburn's protection was Autonomous Recovery Service; Phoenix-as-primary is a different protection posture and does not inherit it | [`docs/03`](03-replication-matrix.md) §1; [`RB-05`](../runbooks/RB-05-replication-lifecycle.md) §2 Phase 2 |
| **Event documentation** — "All recovery and reconstitution events should be well documented, including actions taken and problems encountered … An after-action report with lessons learned should be documented and included for updating the ISCP" (printed page 42) | Timing sheet, RPO attestation, replication-state capture, and the narrative | [`drill-timing-sheet.md`](../checklists/drill-timing-sheet.md); [`evidence/`](../evidence/); [`RB-04`](../runbooks/RB-04-dr-drill.md) §5 |

### 4.1 Re-protection is the real exit criterion

Three of the five activities above are one idea: **after a failover you are running
unprotected until you rebuild the thing that was protecting you.** Until re-protection is
complete, a second event is an unrecoverable event.

| What was protecting you | State immediately after failover | Restored by |
|---|---|---|
| Data Guard standby | **Gone.** The Phoenix primary has no standby; the Ashburn members are down or being rebuilt | [`RB-05`](../runbooks/RB-05-replication-lifecycle.md) §2 Phase 2 |
| Local SYNC leg / RPO 0 | **Gone.** There is no Phoenix-local synchronous standby; the configuration runs Maximum Performance from the moment of the role transition | [`RB-01`](../runbooks/RB-01-switchover.md) §2; [`docs/01`](01-architecture.md) §3 |
| Storage replication | **Reversed or broken.** Replicas were activated; source policies may have been deleted | [`RB-02`](../runbooks/RB-02-failover.md) §4; [`docs/03`](03-replication-matrix.md) §2 |
| Immutable backup copy | **Not following you.** Recovery Service protected the Ashburn database | [`docs/03`](03-replication-matrix.md) §1 |
| Full Stack DR plans | **Pointing the wrong way.** The DR Protection Group peer roles are inverted | [`docs/03`](03-replication-matrix.md) §4 |

Read [`docs/03`](03-replication-matrix.md) §2, "The re-baseline trap", before estimating how
long re-protection takes. Several of these mechanisms re-baseline from zero rather than
resuming, and the answer is measured in hours to days, not minutes.

### 4.2 Formal deactivation

> "Once all activities and steps have been completed and documentation has been updated, the
> ISCP can be formally deactivated. An announcement with the declaration should be sent to
> all business and technical contacts."
> — §4.4, printed page 42 [1]

Deactivation is an announcement made by the same authority that declared the disaster
([`roles-and-responsibilities.md`](../checklists/roles-and-responsibilities.md) §2), sent to
the same list that was notified at Activation
([`contact-roster.md`](../checklists/contact-roster.md) §1). Declaration and deactivation are
a matched pair; an unclosed declaration leaves the organisation unsure whether it is still in
a disaster.

**Reassessment and reauthorization.** NIST requires a judgement on whether the system "has
undergone significant change and will require reassessment and reauthorization" (§4.4,
printed page 41) [1], naming a new or upgraded hardware platform and moving to a new facility
as examples (footnote 34). A region change is a strong candidate. This plan does not carry an
authorisation boundary of its own — see [`docs/07`](07-itil4-alignment.md) §1a, which records
that the commercial OC1 regions used here carry no FedRAMP or DoD authorisation — so the
decision belongs to whoever owns that boundary in your organisation.

---

## 5. Reconstitution exit checklist

The plan is deactivated only when all of these are true:

- [ ] Validation data testing complete; RPO attestation generated and filed in `evidence/`
- [ ] Validation functionality testing complete; **the functional team has signed the validation pack**, not the DBA
- [ ] Users, business owner, and every interconnected partner notified of service restoration
- [ ] Drill and temporary resources torn down; posture returned to steady state
- [ ] **A standby exists again**, and its lag is inside the tier RPO
- [ ] **A fresh full backup of the current primary exists**, in whatever region is now primary
- [ ] Full Stack DR protection groups re-pointed and their plans re-validated
- [ ] Timing sheet, replication-state capture, and after-action narrative written to `evidence/`
- [ ] [`docs/00-record-of-changes.md`](00-record-of-changes.md) updated with what the event taught
- [ ] Deactivation announced by the declaring authority

Anything unticked is an open disaster, whatever the dashboards say.

---

## 6. Known gap in this revision

**There is no after-action report template.** NIST asks for one explicitly (§4.4, printed
page 42) [1], and this repository has the *inputs* — the drill timing sheet, the RPO
attestation script, the replication-state capture, the `evidence/` directory — but no
document that assembles them into the report, and no defined route from a finding to a plan
change beyond `docs/00-record-of-changes.md`. `RB-04` §5 covers evidence and improvement for
a *drill*; a real event is not covered.

Recorded here rather than quietly omitted, consistent with how `docs/07` §Gaps handles G1–G4.

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
   §4.4, printed page 41 (PDF page 55): "The Reconstitution Phase is the third and final
   phase of ISCP implementation and defines the actions taken to test and validate system
   capability and functionality. … If the original facility is unrecoverable, the activities
   in this phase can also be applied to preparing a new permanent location to support system
   processing requirements. This phase consists of two major activities: validating
   successful recovery and deactivation of the plan" (§1, §2); the three validation
   definitions — "Concurrent processing is the process of running a system at two separate
   locations concurrently until there is a level of assurance that the recovered system is
   operating correctly and securely", "Data testing is the process of testing and validating
   recovered data to ensure that data files or databases have been recovered completely and
   are current to the last available backup", "Functionality testing is a process for
   verifying that all system functionality has been tested, and the system is ready to return
   to normal operations" (§3); footnote 33, printed page 41: "According to NIST SP 800-53
   Contingency Plan security controls, information systems are not required to have
   concurrent processing capabilities" (§3); §4.4, printed page 41: "Deactivation of the plan
   is the process of returning the system to normal operations and finalizing reconstitution
   activities to prepare the system against another outage or disruption", "Upon return to
   normal operations, users should be notified by the ISCP Coordinator (or designee) using
   predefined notification procedures", and the reassessment sentence with footnote 34's
   examples "1) new or upgraded hardware platform, and 2) moving to a new facility" (§4,
   §4.2); §4.4, printed page 42 (PDF page 56): "Cleanup is the process of cleaning up work
   space or dismantling any temporary recovery locations, restocking supplies … and readying
   the system for another contingency event", "As soon as reasonable following
   reconstitution, the system should be fully backed up and a new copy of the current
   operational system stored for future recovery efforts", "All recovery and reconstitution
   events should be well documented, including actions taken and problems encountered during
   the recovery and reconstitution efforts. An after-action report with lessons learned
   should be documented and included for updating the ISCP", and "Once all activities and
   steps have been completed and documentation has been updated, the ISCP can be formally
   deactivated. An announcement with the declaration should be sent to all business and
   technical contacts" (§4, §4.2, §6).

### Unverified statements

- The judgement that a second writable EBS copy "would diverge, and reconciling it is worse
  than the outage" (§3) is engineering judgement about this application, not a sourced claim.
  NIST's footnote 33 is cited only for the narrower point that concurrent processing is not
  required.
- The re-protection table in §4.1 states the post-failover state of each protection mechanism.
  The individual mechanism behaviours are sourced in `docs/03`; their aggregation into "you
  are running unprotected until re-protection completes", and the claim that this is the real
  exit criterion, are this plan's framing.
- The exit checklist in §5 is this plan's own construction from NIST's five deactivation
  activities plus the re-protection requirement. NIST provides no checklist.

[1]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf "NIST SP 800-34 Rev. 1"
