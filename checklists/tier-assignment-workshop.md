# Tier Assignment Workshop

Purpose: get the business to own the MTD tiers in `docs/02-mtd-tiers.md`, with a signature.
Tier assignment is a business decision about acceptable loss, not an IT decision about
technology.

**Duration:** half a day. **Attendees:** business process owners, Finance, EBS functional,
IT infrastructure, risk/audit.

## Run order

### 1. Frame the vocabulary (15 min)
Walk through `docs/02-mtd-tiers.md` §1 and the timeline diagram. The point to land:
*RTO is not when the business is working again.* Most later disagreements trace back to
someone hearing "4 hour RTO" and understanding "back in business in 4 hours" — NIST SP 800-34
Rev. 1 defines RTO as "the maximum amount of time that a system resource can remain
unavailable", separate from the MTD for the business process it supports [1].

### 2. Per-process impact (90 min)
For each major EBS process, ask three questions and write the answers down:

| Process | Unavailable 4 hours — what happens? | Unavailable 24 hours? | Cost of losing 1 hour of committed transactions? |
|---|---|---|---|
| Order entry / booking | | | |
| Shipping / fulfilment | | | |
| AP payment runs | | | |
| AR cash application | | | |
| GL / period close | | | |
| Procurement | | | |
| Payroll / HR self-service | | | |
| Reporting / BI | | | |
| Partner / EDI integrations | | | |

### 3. Assign tiers (45 min)
Map each process to Tier 0–3 using §3 of the tier document as the straw model. Expect
pushback that everything is Tier 0. The counter is §4 and the cost column: Tier 0 for
everything is roughly the cost of a second production estate.

### 4. Confront the Exadata floor (30 min)
Present `docs/05-cost-and-teardown.md` §2 honestly. The database cannot be cheaply tiered;
the application stack can. This usually reframes the conversation productively — the
question becomes "which *applications* wait" rather than "can we skip DR for the database".

### 5. Agree the freeze rules (20 min)
- No cross-region failover during period close without CFO sign-off
- No failover mid-`adop` cycle
- If RPO is breached, Concurrent Managers stay down pending Finance clearance

### 6. Sign (10 min)
Record decisions in `docs/02-mtd-tiers.md` §3 and capture signatures below.

## Output

| Process | Agreed tier | RPO accepted | MTD accepted | Owner |
|---|---|---|---|---|
| | | | | |

Business owner __________  Finance __________  CIO __________  Risk __________  Date __________

> Re-run this workshop annually, and after any material change to the business
> (acquisition, new market, new regulatory obligation). Tier assignments go stale quietly.

---

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *Contingency Planning Guide for Federal Information Systems.* NIST Special Publication 800-34 Rev. 1, May 2010 (errata 2010-11-11), accessed 2026-09-01.
   <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf> — Supports: "RTO defines the maximum amount of time that a system resource can remain unavailable before there is an unacceptable impact on other system resources, supported mission/business processes, and the MTD." (§3.2.1, p. 17) (Run order §1).

[1]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf "NIST SP 800-34 Rev. 1 — Contingency Planning Guide for Federal Information Systems"
