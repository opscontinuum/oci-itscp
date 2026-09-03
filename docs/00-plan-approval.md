# Plan Approval

The statement that turns this document set from a *design* into a *plan*: a named authority
affirms that it is complete, that it has been tested sufficiently, and that they own its
continued maintenance and testing. NIST SP 800-34 Rev. 1 puts this element first in its ISCP
template — above "1. Introduction" — at every FIPS 199 impact level [1].

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

These triggers are this plan's own. They cover re-approval of the statement, which is one
part of gap G3 in [`docs/07-itil4-alignment.md`](07-itil4-alignment.md) §3 (no stated
review cadence); the plan-maintenance section G3 asks for in the README is still open.

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

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *Contingency Planning Guide for Federal Information Systems.* NIST Special Publication
   800-34 Rev. 1, May 2010 (errata 2010-11-11), accessed 2026-09-02.
   <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf> —
   Supports: the "Plan Approval" requirement quoted in §2, verbatim from Appendix A, printed
   page A.1-3 (PDF p. 75); the same text appears at A.2-3 (PDF p. 89) and A.3-3 (PDF p. 105).
   The Appendix A introduction (printed A.1-1, PDF p. 73) states "Appendix A.1 can be used
   for low-impact systems, Appendix A.2 for moderate-impact systems, and Appendix A.3 for
   high-impact systems", and each template's table of contents (printed A.1-2, A.2-2, A.3-2)
   lists "Plan Approval" as its first, unnumbered element above "1. Introduction" — the
   opening claim that the statement is required at every impact level and precedes the plan
   body. The sample language on the same pages as the requirement is signed by
   "{System Owner Name}" and "{System Owner Title}", attests the plan "will be tested at
   least annually", cites the last test date and the location of the TT&E material, and
   keeps the plan "under version control" — the four affirmations in §2 and the structure of
   the template statement in §3.

### Unverified statements

- The requirement that the test cited in the statement be a Level 2 Snapshot Standby drill
  or higher, and the list of re-approval triggers, are this plan's own decisions. NIST's
  sample language commits only to testing at least annually and to citing the last test [1];
  the drill levels are defined by this plan in `runbooks/RB-04-dr-drill.md` §1.
- The choice of additional signatories (business owner, CIO, risk) mirrors the sign-off
  lines already used in `checklists/` and is not prescribed by NIST, which requires only
  the designated authority's signature and leaves "other applicable approving signatures"
  to the organisation [1].

[1]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf "NIST SP 800-34 Rev. 1 — Contingency Planning Guide for Federal Information Systems"
