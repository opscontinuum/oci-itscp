# Plan Approval

The statement that turns this document set from a *design* into a *plan*: a named authority
affirms that it is complete, that it has been tested sufficiently, and that they own its
continued maintenance and testing. NIST SP 800-34 Rev. 1 puts this element first in its ISCP
template — above "1. Introduction" — at every FIPS 199 impact level [1][2].

> ### ⚠️ Placeholder signatories only
>
> This repository documents a **hypothetical corporation**. Every name, title, and date below
> is a `{placeholder}`. Do not fill this in here. In your private fork, the signed copy is
> evidence and belongs with the rest of the evidence — see [§4](#4-where-the-signed-copy-lives).

---

## 1. What this is, and what it is not

| Artefact | Question it answers | Signed when |
|---|---|---|
| **This document** | *Is the plan complete, tested, and owned?* | Before the plan is relied on; re-signed on the triggers in §3 |
| [`checklists/dr-authority-matrix.md`](../checklists/dr-authority-matrix.md) | *Who may declare what during an incident, without waiting for whom?* | Before an incident |
| [`checklists/tier-assignment-workshop.md`](../checklists/tier-assignment-workshop.md) | *What loss has the business agreed to accept, per process?* | At the workshop; re-run annually |

These are not duplicates. The authority matrix governs **decisions during execution** — it
can be fully agreed and signed while the plan it executes is still untested. The tier
workshop signs off **inputs** to the plan. Neither says the plan as a whole is complete and
has been exercised. That is what this statement is for, and it is what an assessor asks for
by name.

## 2. What the statement must affirm

NIST SP 800-34 Rev. 1, Appendix A, "Plan Approval" [1], verbatim:

> Provide a statement in accordance with the agency's contingency planning policy to affirm
> that the ISCP is complete and has been tested sufficiently. The statement should also affirm
> that the designated authority is responsible for continued maintenance and testing of the
> ISCP. This statement should be approved and signed by the system designated authority.
> Space should be provided for the designated authority to sign, along with any other
> applicable approving signatures.

So, four things, and a signature block:

1. **Complete** — the plan accurately represents the system as built.
2. **Tested sufficiently** — with a date and a pointer to the test evidence. NIST's sample
   language commits to testing "at least annually" [1]; this plan's own cadence is stricter
   ([`runbooks/RB-04-dr-drill.md`](../runbooks/RB-04-dr-drill.md): quarterly minimum, monthly
   for Tier 0), and the statement should cite the cadence the plan actually commits to.
3. **Owned** — a designated authority is responsible for continued maintenance *and* testing.
4. **Under version control** — the plan is modified as changes occur, and stays under version
   control in accordance with the organisation's contingency planning policy.

The template below adapts NIST's sample language to this plan. It is deliberately specific
about *which* test counts: a Level 1 component test does not demonstrate the plan; a
Level 2 Snapshot Standby drill does (RB-04 §1). A statement that says "tested" without saying
at what level is not worth the signature.

## 3. Approval statement (template)

> As the designated authority for **{system name — e.g. Oracle E-Business Suite on Exadata,
> `us-ashburn-1` → `us-phoenix-1`}**, I certify that this IT service continuity plan (ITSCP) is
> complete, and that the information it contains — architecture
> ([`docs/01-architecture.md`](01-architecture.md)), tier assignments
> ([`docs/02-mtd-tiers.md`](02-mtd-tiers.md)), replication design
> ([`docs/03-replication-matrix.md`](03-replication-matrix.md)), runbooks
> ([`runbooks/`](../runbooks/)), and automation ([`scripts/`](../scripts/)) — is an accurate
> representation of the system, its database, application, storage, and network components
> as deployed on **{approval date}**.
>
> I further certify that the plan identifies the criticality of the system to
> **{organisation name}** through the tier assignments agreed at the tier-assignment
> workshop held on **{workshop date}**, and that the recovery strategies it describes provide
> the ability to recover the system within the MTD of each tier in a manner consistent with
> that criticality and its cost.
>
> I attest that this plan will be exercised at least **{cadence — no less often than the
> RB-04 cadence: quarterly, monthly for Tier 0}**, and at minimum annually with a Level 2
> Snapshot Standby drill. The plan was last tested on **{date of last Level 2 drill}** at
> **Level {2 or 3}**; the timing sheet, RPO attestation, and findings from that drill are at
> **{`evidence/drill-<date>/` or private evidence repository reference}**. Every MTD figure
> in this plan that has not been measured by such a drill remains a *design target*, not a
> commitment.
>
> I accept responsibility for the continued maintenance and testing of this plan. It will be
> modified as changes occur, will remain under version control in this repository, and will
> be re-approved on any of the triggers listed below, in accordance with
> **{organisation name}**'s contingency planning policy.

**Re-approval triggers** — re-sign, do not just re-date:

- Annually, at the same time as the tier-assignment workshop is re-run.
- Any **[MATERIAL]** assumption in `docs/01-architecture.md` §1 changes.
- Any tier assignment changes (`docs/02-mtd-tiers.md` §3).
- A Level 2 drill fails to meet a tier's MTD and the finding is closed by changing the plan
  rather than the estate.
- After a real invocation of RB-02 and the subsequent RB-03 failback.
- The designated authority changes. Approval does not transfer with the job title.

### Signatures

| Role | Name | Title | Signature | Date |
|---|---|---|---|---|
| **Designated authority / system owner** *(required)* | `{name}` | `{title}` | | |
| Business owner | `{name}` | `{title}` | | |
| CIO | `{name}` | `{title}` | | |
| Risk / audit | `{name}` | `{title}` | | |

The designated authority's signature is the one NIST requires [1]; the others are the "other
applicable approving signatures" and mirror the sign-off lines already used in
`checklists/`. Add or remove rows to match your contingency planning policy — but do not
remove the first one.

| | |
|---|---|
| Plan version approved | `{git tag or commit}` |
| Approval supersedes | `{previous approval date, or "initial"}` |
| Next scheduled re-approval | `{date}` |

## 4. Where the signed copy lives

The signed statement is evidence, and carries the same handling rules as the rest of
`evidence/` (see the README's note on that directory). In a private fork, keep the signed
copy alongside the drill output it cites — `evidence/plan-approval-<date>.md` or a scanned
signature page — and record the approved commit or tag so that "the plan that was approved"
is a specific, checkable revision and not whatever `main` happens to be today.

In **this** repository the template stays unsigned. That is not an oversight; it is the point
of the warning at the top.

## References

1. NIST SP 800-34 Rev. 1, *Contingency Planning Guide for Federal Information Systems*
   (May 2010), Appendix A, "Plan Approval". Low-impact template A.1, printed page A.1-3
   (PDF p. 75); moderate-impact template A.2, printed page A.2-3 (PDF p. 89); high-impact
   template A.3, printed page A.3-3 (PDF p. 105). The requirement text is identical in all
   three. Sample language on the same pages commits to annual testing, cites the last test
   date and the location of TT&E material, and keeps the plan under version control.
   *Supports:* §2 (the four things the statement must affirm; the required signature is the
   designated authority's), §3 (structure and content of the template statement).
2. NIST SP 800-34 Rev. 1, Appendix A introduction (printed page A.1-1, PDF p. 73): "Appendix
   A.1 can be used for low-impact systems, Appendix A.2 for moderate-impact systems, and
   Appendix A.3 for high-impact systems." Each template's table of contents (printed A.1-2,
   A.2-2, A.3-2) lists "Plan Approval" as its first, unnumbered element, above
   "1. Introduction".
   *Supports:* the opening claim that the statement is required at every impact level and
   precedes the plan body.
