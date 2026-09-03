# Outage Assessment

**This procedure produces exactly one number: the estimated time to restore service in
Ashburn.** [`RB-02`](../runbooks/RB-02-failover.md) §0 Q4 compares that number against the
remaining MTD budget, and the comparison decides whether a disaster is declared. Everything
else this checklist collects is evidence for the after-action record.

NIST SP 800-34 Rev. 1 §4.2.3 requires it: "To determine how the ISCP will be implemented
following a system disruption or outage, it is essential to assess the nature and extent of
the disruption. The outage assessment should be completed as quickly as the given conditions
permit, with personnel safety remaining the highest priority" (printed page 38) [1].

> ### Safety first, and it is not a formality
>
> NIST puts personnel safety above assessment speed [1]. In this estate no assessor is
> physically near the affected equipment — Oracle operates the regions — so the safety
> constraint usually binds on the *people*, not the estate: a regional event that took out a
> data centre may also have taken out an office, a home, or a person. If an assessor is in a
> disrupted location, they are not an assessor. Pass to the alternate in
> [`roles-and-responsibilities.md`](roles-and-responsibilities.md) §3.1 and say why.

---

## 1. Time budget

The gate is ten minutes end to end. The assessment lives inside it, and runs **concurrently**
with the call tree, not after it ([`docs/08`](../docs/08-phase-activation-notification.md)
§3.1).

| T+ | Activity | Owner |
|---|---|---|
| 0–1 min | Reachability triage — answers RB-02 §0 Q1, Q2, Q3 | Assessment lead |
| 0–4 min | Evidence capture, run in parallel with everything | Assessment lead + DBA |
| 2–6 min | Blast radius: is this the database, the availability domain, or the region? | Assessment + Network |
| 5–8 min | **Estimate**, with a confidence band | Assessment lead |
| 8–10 min | Hand the estimate to the DR Commander; gate decision | DR Commander |

**Overrunning the budget is itself an input.** If the assessment cannot produce an estimate by
T+8, the estimate is *unknown*, and §5 says what unknown means. Do not spend the MTD budget
buying certainty.

---

## 2. Assessment is not triage, and the gate already does the triage

RB-02 §0 Q1–Q3 establish *what is broken*. This procedure establishes *how long it stays
broken*. Run the gate questions first; they are faster and they route most incidents away
from here entirely.

---

## 3. NIST's minimum areas, in a cloud estate

NIST names seven minimum areas (§4.2.3, printed page 38) [1]. Three assume a building the
assessor can walk into. Stated with the reason in each case rather than dropped:

| NIST minimum area | Applies here | How it is answered |
|---|---|---|
| "Cause of the outage or disruption" | **Partly.** The proximate cause is visible; the root cause usually is not, and is not needed for the estimate | OCI Console health, service events, `dg-health.sh`, `check-replication-health.sh` |
| "Potential for additional disruptions or damage" | **Yes** — and it is the highest-value question here | Is the event bounded, spreading, or ongoing? See §4 step 3 |
| "Status of physical infrastructure (… computer room, electric power, telecommunications, HVAC)" | **Answered by Oracle, not by you** | OCI status page and the service event; the operator has no physical access. Record what Oracle states and the time it was stated |
| "Inventory and functional status of system equipment" | **Yes**, as control-plane state | Instance lifecycle states, VM cluster state, replica states — §4 step 2 |
| "Type of damage to system equipment or data (water, fire and heat, physical impact, electrical surge)" | **Not applicable** as written. The equivalent is **data** damage: corruption, ransomware encryption, logical error | If the cause may be cyber, this is no longer only a continuity event — escalate per [`roles-and-responsibilities.md`](roles-and-responsibilities.md) §5 |
| "Items to be replaced (hardware, software, firmware, supporting materials)" | **Not applicable** in the normal path — Phoenix is pre-provisioned. Becomes applicable only if standby capacity is refused | [`docs/02`](../docs/02-mtd-tiers.md) §4; escalation to the OCI account team |
| "Estimated time to restore normal services" | **Yes — this is the output** | §5 |

---

## 4. Procedure

### Step 1 — Reachability and role state (T+0 to T+1)

```bash
./scripts/dataguard/dg-health.sh            # roles, protection mode, FSFO state, lag
./scripts/oci/check-replication-health.sh   # volume group, FSS, object, FSDR member state
```

Answers RB-02 §0 Q1 and Q2. If the primary is openable, stop — this is not a failover.

### Step 2 — Evidence capture (T+0 to T+4, in parallel)

```bash
./scripts/dataguard/capture-lag-snapshot.sh    # transport + apply lag at the moment of loss
./scripts/oci/capture-replication-state.sh     # replica timestamps across every tier
```

**Run this even if you expect not to declare.** It is unrecoverable once roles change, it is
the basis of the data-loss statement Finance will ask for, and it costs four minutes of
somebody else's time. RB-02 §1 requires it on the declared path; this checklist pulls it
earlier so the evidence exists regardless of the decision.

### Step 3 — Blast radius (T+2 to T+6)

The single most important distinction, because it maps directly onto a duration:

| Radius | Signal | Typical restore path | Estimate band |
|---|---|---|---|
| **Database only** | ExaDB-D unhealthy, availability domain otherwise serving | Local FSFO already handled it, or local recovery | Minutes to ~1 hr |
| **One availability domain** | AD-1 resources down, AD-2 healthy, load balancer still serving | Bring AD-2 nodes into service (RB-02 §0 Q2a) | ~15–60 min, in region |
| **Whole region** | Multiple services degraded in `us-ashburn-1`; OCI service event open | Cross-region failover | **Oracle's estimate, or unknown** |
| **Data, not infrastructure** | Infrastructure healthy, data wrong — corruption, encryption, bad change | Flashback, point-in-time restore, or Recovery Service | Depends on detection lag, not on infrastructure |

**The fourth row does not belong to this gate.** A logical or cyber event may make Phoenix
just as wrong as Ashburn, because Data Guard replicates the damage faithfully. Failing over
does not help and may destroy the evidence. Route it to
[`roles-and-responsibilities.md`](roles-and-responsibilities.md) §5 and to the immutable copy
in [`docs/03`](../docs/03-replication-matrix.md) §1.

### Step 4 — Ask Oracle, and record the answer with a timestamp

For a regional event, the operator's own estimate is the only credible input to a repair
time. Open a Severity 1 with the CSI in [`contact-roster.md`](contact-roster.md) §5, check
the OCI status page and the tenancy's service events, and **write down what was said and
when**. An estimate with no timestamp is worthless twenty minutes later.

---

## 5. Producing the estimate

**Give a band and a confidence, never a point estimate.** "Two to six hours, low confidence"
is usable by the gate. "About four hours" implies a precision nobody has, and invites the
Commander to treat it as fact.

| Estimate | Confidence | What the gate does with it |
|---|---|---|
| Comfortably **inside** remaining MTD budget | Any | Do not declare. Re-evaluate at T+30 (RB-02 §0 R3) |
| Comfortably **outside** remaining MTD budget | Any | Declare |
| **Straddles** the budget | High | Re-evaluate at T+30; set the re-evaluation time explicitly |
| **Straddles** the budget | Low | **Declare.** See below |
| **Unknown** — no credible basis | — | **Declare**, if the radius is regional |

### 5.1 Unknown means declare, and that is deliberate

When the radius is regional and no credible repair estimate exists, the honest reading is not
"wait and see" — it is that the budget is being spent at a known rate against an unknown
duration. RB-02 §0 already says it: "Declaring late burns the margin a cross-region failover
needs to still land inside MTD," and "Do not wait for certainty; the decision gate exists to
be used."

The asymmetry is real but bounded. An unnecessary failover costs the return trip — full
baseline copies of every storage tier ([`RB-03`](../runbooks/RB-03-failback.md) §1,
[`docs/03`](../docs/03-replication-matrix.md) §2), which is expensive but survivable. A
late declaration costs the MTD, which is the commitment the business signed.

*(Unverified: the decision rule in this table, and the judgement that a late declaration is
worse than an unnecessary failover, are this plan's engineering judgement. NIST requires that
an estimated time to restore be produced and does not say what to do when it cannot be.)*

---

## 6. If the plan is not available

> "Personnel with outage assessment responsibilities should understand and be able to perform
> these procedures in the event the plan is inaccessible during the situation."
> — §4.2.3, printed page 39 [1]

This repository could be unreachable in exactly the event it exists for. The assessment
reduces to five questions that a trained assessor answers from memory — the closed-book
requirement in [`contingency-training.md`](contingency-training.md) §6:

1. Can the primary database be opened? *(No → continue)*
2. Did the local standby take over, and is an application tier serving? *(Yes → not a cross-region event)*
3. Is this one availability domain, the whole region, or the data itself?
4. What did Oracle say, and when?
5. How long until Ashburn is back — band and confidence — and how does that compare with what is left of the MTD?

Anyone on the assessment rota who cannot answer these without the document is not yet trained
for the role.

---

## 7. Assessment record

Copy into `evidence/` as `outage-assessment-<UTC timestamp>.md`. Complete it even when the
decision is *do not declare* — a near-miss is the cheapest evidence this programme ever gets.

```
Incident ....................... {id}
Assessment started (UTC) ....... {timestamp}
Assessment lead ................ {name}    Safety exceptions: {none | detail}

Gate answers
  Q1 primary openable .......... {yes|no}
  Q2 local FSFO promoted ....... {yes|no}      Q2a app tier serving: {yes|no}
  Q3 region / infra lost ....... {yes|no}

Blast radius ................... {database | availability domain | region | data}
Cause (proximate) .............. {text | unknown}
Potential for further damage ... {bounded | spreading | ongoing | unknown}
Cyber cause suspected .......... {yes|no}     -> if yes, escalate per roles §5
Oracle statement ............... {text} at {timestamp}
Control-plane status ........... {summary from step 1}
Evidence captured .............. {lag snapshot: yes|no} {replication state: yes|no}

ESTIMATED TIME TO RESTORE ...... {band}  confidence {high|medium|low|unknown}
MTD budget remaining ........... {minutes}  (tier {n} MTD, minus elapsed, minus ~60 min RTO)
Recommendation ................. {declare | do not declare | re-evaluate at T+{n}}

Delivered to ................... {DR Commander name} at {timestamp}
Decision taken ................. {declared | not declared} at {timestamp} by {name}
```

---

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *NIST Special Publication 800-34 Rev. 1, Contingency Planning Guide for Federal
   Information Systems.* National Institute of Standards and Technology, May 2010 (errata
   2010-11-11), accessed 2026-09-02.
   <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf> —
   Supports: §4.2.3, printed page 38 (PDF page 52): "To determine how the ISCP will be
   implemented following a system disruption or outage, it is essential to assess the nature
   and extent of the disruption. The outage assessment should be completed as quickly as the
   given conditions permit, with personnel safety remaining the highest priority. When
   possible, the Outage Assessment Team is the first team notified of the disruption", and the
   seven minimum areas "Cause of the outage or disruption; Potential for additional
   disruptions or damage; Status of physical infrastructure (e.g., structural integrity of
   computer room, condition of electric power, telecommunications, and heating, ventilation
   and air-conditioning [HVAC]); Inventory and functional status of system equipment (e.g.,
   fully functional, partially functional, nonfunctional); Type of damage to system equipment
   or data (e.g., water, fire and heat, physical impact, electrical surge); Items to be
   replaced (e.g., hardware, software, firmware, supporting materials); and Estimated time to
   restore normal services" (introduction, §3); §4.2.3, printed page 39 (PDF page 53):
   "Personnel with outage assessment responsibilities should understand and be able to perform
   these procedures in the event the plan is inaccessible during the situation. Once impact to
   the system has been determined, the appropriate teams should be notified of updated
   information and the planned response to the situation. Based upon the results of the outage
   assessment, ISCP notifications may be revisited and expanded" (§6, §7); Appendix A.2 Sample
   ISCP Template (Moderate Impact System) §3.3, printed page A.2-7 (PDF page 93): "Following
   notification, a thorough outage assessment is necessary to determine the extent of the
   disruption, any damage, and expected recovery time. … Assessment results are provided to
   the ISCP Coordinator to assist in the coordination of the recovery", and "Procedures should
   include notation of items that will need to be replaced and estimated time to restore
   service to normal operations" (introduction, §3, §7).

### Unverified statements

- The time budget in §1, and the placement of the assessment inside the ten-minute gate, are
  this plan's engineering judgement, derived from the gate in `RB-02` §0. NIST requires only
  that assessment be "completed as quickly as the given conditions permit".
- The estimate-band decision table in §5, including the rule that an unknown estimate on a
  regional radius means declare, is this plan's engineering judgement. NIST does not address
  the unknown-estimate case.
- The blast-radius bands in §4 step 3 are indicative durations, not measurements. They become
  credible only once a Level 2 drill has timed the corresponding recovery paths
  (`runbooks/RB-04-dr-drill.md` §5).
- The judgement that a logical or cyber event replicates faithfully to the standby and is
  therefore outside this gate follows from the design in `docs/01` and `docs/03`; it is stated
  there and restated here, not independently sourced in this document.

[1]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf "NIST SP 800-34 Rev. 1"
