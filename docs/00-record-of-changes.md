# 00 — Record of Changes

This page is the plan's **record of changes**: which part of the plan changed, what changed,
when, and who signed it off. NIST SP 800-34 Rev. 1 §3.6 requires one and requires it to be
**inside the plan** [1]. Git history is not a substitute: the plan is read during an outage as a
standalone document — often printed, when the repository may be exactly what is unreachable —
and a reader holding a paper copy has no `git log`.

> **This is a public example repository.** The rows below are seeded from this repository's
> real git history so the record is accurate from day one, but the plan describes a hypothetical
> corporation with no real estate behind it. In your private fork, keep this file and continue
> the table; do not inherit these rows as if they were your own change history.

## 1. Format

The four columns are NIST's, from Table 3-7 *Sample Record of Changes* [1], which is also the
form NIST's own plan templates carry as their closing appendix, "Document Change Page" [2]:

| NIST column | How it is used in this repository |
|---|---|
| **Page #** | The plan has no page numbers, so this holds the file path(s) and, where useful, the section (`docs/01-architecture.md` §5.1). A printed copy carries the same headings, so the reference survives printing. |
| **Change Comment** | What changed and why, in one or two lines. The git short SHA is appended in parentheses so the full diff can be found when the repository *is* reachable. |
| **Date of Change** | Date the change was committed, ISO 8601 (`YYYY-MM-DD`). |
| **Signature** | Who approved the change. NIST assigns this to the ISCP Coordinator [1]. This example repository has no approval authority, so the column records the git author of the commit; a real plan replaces that with the coordinator's name or initials at sign-off. |

**Rule:** every commit that changes plan content adds a row here in the *same* commit. A change
without a row is a change the printed plan does not know about. Changes to tooling only
(`scripts/`, `terraform/`) that do not alter what a reader of the plan would do may be omitted.

## 2. Record of Changes

| Page # | Change Comment | Date of Change | Signature |
|---|---|---|---|
| All | Initial IT service continuity plan for EBS on Exadata, Ashburn to Phoenix: `docs/01`–`05` (architecture, MTD tiers, replication matrix, monitoring, cost and teardown), `runbooks/RB-01`–`RB-05`, `checklists/`, posture and health-check scripts, Terraform inventory template (`752b7e1`) | 2026-09-01 | Wicnere CI (git author) |
| `README.md`; `evidence/README.md` | Document the repository as a worked example of a hypothetical corporation; add scenario, "How to use this repo", scope and limitations, planned build-out; add `evidence/` handling note and the `.gitignore` Markdown gap (`bf29d45`) | 2026-09-01 | Wicnere CI (git author) |
| `docs/00-record-of-changes.md`; `README.md` | Add this record of changes and link it from the README reading list. Closes issue #1 | 2026-09-02 | Wicnere CI (git author) |

## 3. Relationship to plan review

NIST's §3.6 asks for two different things. The first is that the plan "be reviewed for accuracy
and completeness at an organization-defined frequency or whenever significant changes occur"
[3] — *when* the plan is looked at. The second is this record — *what changed* when it was.
The first is the review-cadence gap tracked as **G3** in the ITIL 4 alignment note; this file
does not close G3, and closing G3 without this file would still leave no change record. The
two are kept separate on purpose: a review that finds nothing to change produces no row here,
and a row here does not evidence that a review took place.

## 4. Source notes

Recorded so the next reader does not have to re-derive them:

- §3.6's text refers to "Table " with the number missing — an unresolved field code in the
  published PDF. The caption on the same page reads **Table 3-7**, but the List of Tables
  (printed page viii) lists it as **Table 3-6**. This file follows the caption.
- §3.6 says the record "should be integrated into the plan as discussed in Section 4.1", but
  §4.1 *Supporting Information* (printed page 35) does not mention it. The placement NIST
  actually uses is in its own templates: the last appendix of each, "Document Change Page" [2].
- NIST's own front matter carries a change table (printed pages ix–x) headed **Errata**, with
  columns Date / Type / Change / Page Number. It is a fair model for the *content* of a change
  comment, but it is not the Table 3-7 format.

## References

1. NIST SP 800-34 Rev. 1, *Contingency Planning Guide for Federal Information Systems*
   (May 2010, errata through 11 November 2010), §3.6 "Plan Maintenance", printed page 32
   (PDF page 46), including Table 3-7 *Sample Record of Changes*.
   <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf#page=46>
   *Supports:* the requirement — "The ISCP Coordinator should record plan modifications using
   a record of changes, which lists the page number, change comment, and date of change. The
   record of changes, depicted in Table , should be integrated into the plan as discussed in
   Section 4.1." — and the four column headings Page # / Change Comment / Date of Change /
   Signature.
2. NIST SP 800-34 Rev. 1, Appendix A sample ISCP templates, "Document Change Page": Appendix L
   of the low-impact template (page A.1-14, PDF page 86), Appendix M of the moderate- and
   high-impact templates (pages A.2-16 and A.3-16, PDF pages 102 and 118).
   *Supports:* placing the record inside the plan as an appendix, headed "Record of Changes",
   with columns Page No. / Change Comment / Date of Change / Signature.
3. NIST SP 800-34 Rev. 1, §3.6 "Plan Maintenance", printed page 31 (PDF page 45).
   *Supports:* the review-frequency requirement that §3 above distinguishes from this record.
4. This repository's git history, `git log --stat` on `main`.
   *Supports:* the seeded rows in §2 (commits `752b7e1` and `bf29d45`, both 2026-09-01).
