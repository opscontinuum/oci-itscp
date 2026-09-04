# 00 — Record of Changes

This page is the ITSCP's **record of changes**: which part of the plan changed, what changed,
when, and who signed it off. NIST SP 800-34 Rev. 1 §3.6 requires one — "The ISCP Coordinator
should record plan modifications using a record of changes, which lists the page number, change
comment, and date of change" — and requires it to be "integrated into the plan" [1]. Git
history is not a substitute: the plan is read during an outage as a standalone document, often
printed, when the repository may be exactly what is unreachable, and a reader holding a paper
copy has no `git log`.

> **This is a public example repository.** The rows below are seeded from this repository's
> real git history so the record is accurate from day one, but the plan describes a hypothetical
> corporation with no real environment behind it. In your private fork, keep this file and continue
> the table; do not inherit these rows as if they were your own change history.

## 1. Format

The four columns are NIST's, from Table 3-7 *Sample Record of Changes* on the same page as the
requirement [1]. NIST's own sample plan templates carry the same table, headed "Record of
Changes", as the closing appendix of each template under the title "Document Change Page" [1].
This plan keeps NIST's name for the artefact, *record of changes*, because that is the term the
requirement uses; "Document Change Page" is only the appendix title in the templates. It is
placed first rather than last because the first question a reader with a printed copy has to
answer is whether the copy is current, and because `docs/` is a reading order, not the bound
appendix structure of a single document.

| NIST column | How it is used in this repository |
|---|---|
| **Page #** | The plan has no page numbers, so this holds the file path(s) and, where useful, the section (`docs/01` §5.1). A printed copy carries the same headings, so the reference survives printing. "All" means every document, runbook and checklist. |
| **Change Comment** | What changed and why, in a few lines. The git short SHA is appended in parentheses so the full diff can be found when the repository *is* reachable. The row for a change is written in the same commit as the change, so it cannot carry its own SHA; that SHA is added when the next row is written. |
| **Date of Change** | Date the change was committed, ISO 8601 (`YYYY-MM-DD`). |
| **Signature** | Who approved the change. NIST assigns this to the plan owner, in its vocabulary the ISCP Coordinator [1]. This example repository has no approval authority, so the column records the git author of the commit; a real ITSCP replaces that with the plan owner's name or initials at sign-off. |

**Rule:** every commit that changes plan content adds a row here in the *same* commit. A change
without a row is a change the printed plan does not know about. Changes to tooling only
(`scripts/`, `terraform/`) that do not alter what a reader of the plan would do may be omitted;
where such a change lands together with document changes, the row names the documents and
mentions the tooling.

## 2. Record of Changes

Oldest first. Rows are derived from `git log` on `main`; the short SHA in each row is the
evidence for it.

| Page # | Change Comment | Date of Change | Signature |
|---|---|---|---|
| All | Initial ITSCP for EBS on Exadata, Ashburn to Phoenix: `docs/01`–`05` (architecture, MTD tiers, replication matrix, monitoring, cost and teardown), `runbooks/RB-01`–`RB-05`, `checklists/`, posture and health-check scripts, Terraform inventory template (`752b7e1`) | 2026-09-01 | Wicnere CI (git author) |
| `README.md`; `evidence/README.md` (new) | Document the repository as a worked example of a hypothetical corporation; add scenario, "How to use this repo", scope and limitations, planned build-out; add `evidence/` handling note and the `.gitignore` Markdown gap (`bf29d45`) | 2026-09-01 | Wicnere CI (git author) |
| All; `docs/07` (new); `docs/references.md` (new) | Review pass: every document, runbook and checklist gains numbered inline source markers and a References section, with the consolidated index in `docs/references.md`; statements with no source are marked unverified. Design corrections against Oracle documentation (Full Stack DR member types and billing, Object Storage replication does not copy pre-existing objects, File Storage NFSv3 and 15-minute minimum interval, no cross-region Recovery Service copy, snapshot standby and reinstate prerequisites, ExaDB-D CLI group and OCPU floor, corrected My Oracle Support note IDs). MTD = RTO + WRT stated as the plan's own decomposition. Eight referenced-but-absent scripts added; `docs/07` ITIL 4, NIST and DoD alignment added (`e9d925e`) | 2026-09-01 | Wicnere CI (git author) |
| `docs/01`–`05`, `docs/07`, `runbooks/RB-01`–`RB-05`, `checklists/`; `docs/06` (new); `docs/citation-audit.md` (new) | Adversarial review remediation: Data Guard Broker steps around planned switchover and unplanned failover, RPO 0 stated as conditional; Windows tiers split across Ashburn AD-1 and AD-2 with unique physical names and Oracle's logical-host-names pattern; volume model made explicit; Recovery Service protects the primary only, Phoenix copy is an RMAN backup of the standby; public load balancer behind WAF; transport lag as the RPO signal and apply lag as the RTO signal; citation-audit findings applied; `docs/06` test environments added (`bc11d62`) | 2026-09-01 | Wicnere CI (git author) |
| `docs/01` §1 (A6), §5.3 | State the Remote Peering dependency and its unverified bandwidth guarantee (`004326f`) | 2026-09-01 | Wicnere CI (git author) |
| `README.md`; `docs/03`, `docs/04`, `docs/05`; `terraform/` (root module and ten modules, new) | Terraform for the DR environment, apply-locked and verified offline, never applied; `docs/03`–`05` and the README updated to match (`1a9a032`) | 2026-09-01 | Wicnere CI (git author) |
| `docs/00` (new); `README.md`; `docs/references.md` | Add this record of changes, link it from the README reading list, and index it in `docs/references.md`. Closes issue #1 | 2026-09-02 | Wicnere CI (git author) |
| `skills/itscp-compliance-audit/SKILL.md` (new); `docs/07` §1a | Add a skill that audits the plan against NIST SP 800-34 Rev. 1, the SP 800-53 Rev. 5 CP family, FedRAMP High, DoDI 8510.01 and CNSSI 1253, with every requirement starting refuted; name the audited artefact the ITSCP and state the ISCP crosswalk it is assessed through (`a298997`, `0b4b772`) | 2026-09-02 | Wicnere CI (git author) |
| All | Name this plan the ITSCP throughout and reserve "ISCP" for NIST's own artefact; extend the record-of-changes seed and bring it into the plan's citation style (`6339f75`, `46f6e60`) | 2026-09-02 | Wicnere CI (git author) |
| `docs/00-plan-approval.md` (new); `README.md`; `docs/references.md` | Add the Plan Approval statement NIST SP 800-34 Rev. 1 Appendix A places above "1. Introduction" at every FIPS 199 impact level, unsigned by design; make the ISCP/ITSCP distinction explicit in it; bring its citations into the citation-audit format. Closes issue #2 (`b20d865`, `31af003`, `a1f0389`) | 2026-09-02 | Wicnere CI (git author) |
| `checklists/contingency-training.md` (new); `docs/07` §1a; `README.md` | Add the contingency training program NIST keeps separate from drills — annual syllabus, new-joiner path, closed-book evidence for CP-3 — and narrow the CP-3 claim in `docs/07` accordingly. Closes issue #4 (`4b27c58`) | 2026-09-02 | Wicnere CI (git author) |
| `checklists/contact-roster.md` (new); `README.md` | Add the contact roster and call tree required by NIST SP 800-34 Rev. 1 §4.2.2, including the external and interconnected-system POCs and the unreachable-contact procedure. Closes issue #3 (`0c701b2`) | 2026-09-02 | Wicnere CI (git author) |
| `docs/08`, `docs/09`, `docs/10` (new); `checklists/roles-and-responsibilities.md` (new); `checklists/outage-assessment.md` (new); `README.md` | Add the concept-of-operations overview of the three ISCP phases NIST SP 800-34 Rev. 1 §4.1 expects, one document per phase, each routing to the runbook that performs the work and stating what this plan does not have; add the roles, teams and line of succession the phases depend on; add the outage assessment procedure that produces the repair estimate the `RB-02` §0 gate consumes | 2026-09-02 | Wicnere CI (git author) |

## 3. Relationship to plan review

NIST's §3.6 asks for two different things. The first is that the plan "be reviewed for accuracy
and completeness at an organization-defined frequency or whenever significant changes occur"
[1] — *when* the plan is looked at. The second is this record — *what changed* when it was.
The first is the review-cadence gap **G3** in `docs/07` §3, which recommends a "Plan
maintenance" section in the README; this file does not close G3, and closing G3 without this
file would still leave no change record. The two are kept separate on purpose: a review that
finds nothing to change produces no row here, and a row here does not evidence that a review
took place. `docs/07` §1a maps plan maintenance to NIST SP 800-53 Rev. 5 CP-2 d–f; this record
is the artefact that shows an assessor the plan was in fact updated.

## 4. Source notes

Recorded so the next reader does not have to re-derive them [1]:

- §3.6's text refers to "Table " with the number missing — an unresolved field code in the
  published PDF. The caption on the same page (printed page 32) reads **Table 3-7**, but the
  List of Tables (printed page viii) lists it as **Table 3-6**. NIST's own inconsistency; this
  file follows the caption.
- §3.6 says the record "should be integrated into the plan as discussed in Section 4.1", but
  §4.1 *Supporting Information* (printed page 35) does not mention it, and §4.5 *Plan
  Appendices* (printed page 42) does not list it. The placement NIST actually uses is in its own
  templates: the last appendix of each, "Document Change Page".
- NIST's front matter carries a change table (printed pages ix–x) headed **Errata**, with
  columns Date / Type / Change / Page Number. It is a fair model for the *content* of a change
  comment, but it is not the Table 3-7 format and is not NIST's record of changes for itself.

## References

This document is a synthesis: every statement about product behavior or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *NIST Special Publication 800-34 Rev. 1, Contingency Planning Guide for Federal
   Information Systems.* National Institute of Standards and Technology, May 2010 (errata
   2010-11-11), accessed 2026-09-02.
   <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf> —
   Supports: §3.6 "Plan Maintenance", printed page 32 (PDF page 46): "The ISCP Coordinator
   should record plan modifications using a record of changes, which lists the page number,
   change comment, and date of change. The record of changes, depicted in Table , should be
   integrated into the plan as discussed in Section 4.1", and Table 3-7 *Sample Record of
   Changes* with columns Page # / Change Comment / Date of Change / Signature (introduction,
   §1, §4); §3.6, printed page 31: "the plan should be reviewed for accuracy and completeness
   at an organization-defined frequency or whenever significant changes occur to any element
   of the plan" (§3); Appendix A templates, "Document Change Page", headed "Record of
   Changes" with columns Page No. / Change Comment / Date of Change / Signature, at A.1-14
   (PDF page 86), A.2-16 (PDF page 102) and A.3-16 (PDF page 118) (§1, §4); List of Tables,
   printed page viii, entry "Table 3-6: Sample Record of Changes ... 32" (§4); §4.1, printed
   page 35, and §4.5, printed page 42, contain no mention of the record of changes (§4);
   "Errata" table, printed pages ix–x, columns Date / Type / Change / Page Number (§4).

### Unverified statements

- The mapping of NIST's "Page #" to a file path and section, and of "Signature" to the git
  author, is this plan's own decision for a repository without page numbers or a signing
  authority; NIST does not address version-controlled plans.
- The change comments in §2 are summaries of the corresponding commit messages, not of the
  diffs themselves.

[1]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf "NIST SP 800-34 Rev. 1"
