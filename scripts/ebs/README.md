# EBS SQL helpers

## cmclean.sql — NOT VENDORED

`cmclean.sql` is Oracle-supplied and distributed through My Oracle Support
(Doc ID 134007.1, *Concurrent Processing - CMCLEAN.SQL - Non Destructive Script to Clean
Concurrent Manager Tables* [1][2]). It is not redistributable, so it is deliberately absent
here.

**Applicability caveat:** a public source states that note 134007.1 "is valid for
Applications versions 10.7 to 12.1.3" [2], and the publicly available copy of the EBS 12.2
business-continuity note contains no `cmclean` step [3]. `cmclean.sql` remains a widely used
practice for post-failover Concurrent Manager cleanup, but confirm its applicability to your
12.2 patch level with Oracle Support before relying on it in a drill or a real failover
(`checklists/pre-failover-precheck.md` §C).

Download the current version for your EBS release and place it in this directory as
`cmclean.sql`. `scripts/windows/Start-EBSAppTier.ps1` checks for it and fails loudly
rather than starting Concurrent Managers without it.

## Usage

Run as APPS with **all** Concurrent Managers down, then COMMIT. Required after any
Data Guard role transition — stale FND_CONCURRENT_QUEUES and ICM rows from the former
primary otherwise prevent managers from starting, with a confusing failure mode.

---

## References

This document is a synthesis: every statement about product behaviour or a standard is derived
from the sources below, and any statement that could not be traced to a source is marked as
unverified. Numbers restart per document. The consolidated index is `docs/references.md`.

1. *Concurrent Processing - CMCLEAN.SQL - Non Destructive Script to Clean Concurrent Manager Tables.* My Oracle Support Doc ID 134007.1, Oracle. Unverifiable by URL: login-gated (My Oracle Support). Title corroborated only by [2].
2. *Be Warned: cmclean.sql Is Dangerous!* Maris Elsins, Pythian blog, 2013-07-18, accessed 2026-09-01.
   <https://www.pythian.com/blog/be-warned-cmclean-sql-is-dangerous/> — Supports: corroborates the title of Doc ID 134007.1; states the note "is valid for Applications versions 10.7 to 12.1.3".
3. *Business Continuity for Oracle EBS R12.2* (third-party copy of My Oracle Support Doc ID 1963472.1). pdfcoffee.com, undated, accessed 2026-09-01.
   <https://pdfcoffee.com/business-continuity-for-oracle-ebsr122-pdf-free.html> — Supports: the copy contains no `cmclean` step; its post-transition cleanup is `fnd_net_services.remove_system`, `fnd_conc_clone.setup_clean`, and `ad_zd_fixer.clear_valid_nodes_info`.

[1]: #references "MOS Doc ID 134007.1 — unverifiable by URL (login-gated)"
[2]: https://www.pythian.com/blog/be-warned-cmclean-sql-is-dangerous/ "Be Warned: cmclean.sql Is Dangerous! — Pythian"
[3]: https://pdfcoffee.com/business-continuity-for-oracle-ebsr122-pdf-free.html "Business Continuity for Oracle EBS R12.2 — third-party copy on pdfcoffee.com"
