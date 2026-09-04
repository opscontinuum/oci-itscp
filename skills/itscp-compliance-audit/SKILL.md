---
name: itscp-compliance-audit
description: Adversarial audit of this IT service continuity plan (ITSCP) against NIST SP 800-34 Rev. 1, the NIST SP 800-53 Rev. 5 CP family, the FedRAMP High baseline, DoDI 8510.01 and CNSSI 1253. Every requirement starts REFUTED, every requirement gets a verdict, and "not assessed" is not a verdict. Produces docs/compliance-audit.md.
---
This skill drives a compliance audit of the plan in this repository to the same standard as
`docs/citation-audit.md`: the default position for every requirement is *refuted* until a
sentence in a repository file proves otherwise, and every requirement in scope gets a row
with a verdict. Read `docs/citation-audit.md` first. Its method paragraph, its verdict
vocabulary and its summary table are the model; anything softer than that document is a
downgrade for this repository and will read as one.

The audit covers five instruments. Two are fully readable, one is readable in a superseded
edition, one is marked legacy by its own issuer, and one is behind a login wall. The skill
says which is which and what the auditor does about each. It does not let the auditor
paraphrase an instrument from memory.

## 1. Scope and the rule that makes this an audit

**In scope.** `README.md`, `docs/01`–`docs/07`, `runbooks/RB-01`–`RB-05`, every file in
`checklists/`, `evidence/README.md`, `scripts/ebs/README.md`, `scripts/dataguard/tnsnames-tuning.md`,
`terraform/README.md`. Scripts and Terraform are evidence only where a document points at them.

**What is being audited against what.** The document under audit is an IT service continuity
plan (ITSCP), the ITIL service-level artefact named in the `README.md` title. NIST SP 800-34
specifies an Information System Contingency Plan (ISCP), a system-level artefact, and the
other four instruments select or parameterise SP 800-53 controls written for that ISCP. The
ITSCP aligns *to* the ISCP structure; it is not one. Every row therefore assesses an ISCP
requirement against this ITSCP by way of the crosswalk in `docs/07-itil4-alignment.md` §1a,
and a finding holds or fails at that crosswalk: a runbook is the ITSCP's disaster recovery
plan, the tier workshop is its BIA, "declare disaster" is its activation. Write "the ITSCP"
or "the plan" for the document under audit and "ISCP" only inside a quotation or when naming
NIST's or FedRAMP's own artefact. An auditor who conflates the two will cite the wrong
instrument for the finding.

**The rule.** A requirement PASSES only when the report quotes the sentence from a repository
file that satisfies it, with file path and section heading. "The runbooks cover this" is not
evidence. "The plan clearly intends" is not evidence. If the auditor cannot paste the
sentence, the verdict is not PASS.

**Verdicts.** Exactly one per row, from this list:

| Verdict | Meaning | What the row must carry |
|---|---|---|
| PASS | A repository sentence satisfies the whole requirement. | Path, section, verbatim quote. |
| PARTIAL | Part of the requirement is satisfied, or the artefact exists but is a blank template. | Path, section, quote, and the missing part named. |
| REFUTED | Nothing in the repository satisfies it. | The places searched, and the closest thing found (or "nothing"). |
| NOT APPLICABLE | The instrument itself, or the plan's stated scope, excludes the requirement. | The instrument sentence that excludes it (for example a withdrawal line, or "a low-impact system is not required to have offsite data storage capabilities"), or the plan sentence that states the scope. Never the auditor's opinion. |
| INACCESSIBLE | The requirement text could not be read. | HTTP status or wall type, URL, date of attempt, and the fallback evidence used (issuing site's listing, a superseded edition, a secondary source), exactly as `docs/citation-audit.md` does for My Oracle Support notes and the DoDI 3020.26 PDF. |

There is no "not assessed", "deferred", "out of scope for this pass" or "see previous
audit". A requirement the auditor did not get to is a requirement the audit did not cover,
and the summary table must say so by count so the reader can reject the audit.

**Withdrawn controls** are rows too. SP 800-53 Rev. 5 withdraws CP-2(4), CP-5, CP-7(5),
CP-9(4), CP-10(1), CP-10(3) and CP-10(5). Each gets NOT APPLICABLE with the withdrawal line
quoted ("[Withdrawn: Incorporated into CP-2(3).]" and so on). That is how the count of rows
stays equal to the count of identifiers in the instrument.

## 2. Before writing a row: intake of what is already known

The audit reports *movement*, not a restatement of known items. Do this before reading any
instrument:

1. **Open issues.** `gh issue list --repo opscontinuum/oci-itscp --state all --json number,title,state,body`.
   On 2026-09-02 the open issues were #1 (Record of Changes, §3.6 / Table 3-7), #2 (Plan
   Approval, App. A printed A.1-3 / A.2-3 / A.3-3), #3 (contact list and call tree, §4.2.2
   printed 37) and #4 (contingency training, §3.5.2 printed 28). Read each body: they model
   the citation style this audit must match (instrument, section, printed page, PDF page link,
   verbatim quote, what the repo already has, suggested shape, related controls).
2. **`docs/07-itil4-alignment.md` §1a and its Gaps table.** G1 (no minimum business continuity
   objective per tier), G2 (no risk register), G3 (no review and maintenance cadence), G4 (no
   availability-versus-continuity boundary). Also T12 ("No statement of how often the plan is
   reviewed") and T13/T14 (two-AD app tier; RPO 0 conditions).
3. **Reconcile.** Every row that lands on a known item carries the identifier in its
   Movement column: `KNOWN #1`, `KNOWN G3`, `KNOWN #4 (narrower: see row)`. A row whose
   requirement was known and is now satisfied carries `CLOSED #n` with the closing quote. A
   row that is new carries `NEW`. The summary counts NEW, KNOWN and CLOSED separately.

Do not re-derive G1–G4 or #1–#4 from the instruments as if they were discoveries. Cite them.

## 3. The instruments, and how each one was reached

Record the access log in the report exactly as `docs/citation-audit.md` records its "Tool
limits encountered" and "URLs fetched" sections. The statuses below were observed on
2026-09-02 with `curl` from a WSL2 host; re-run them, do not copy them.

| Instrument | Where read | Status observed | Pin |
|---|---|---|---|
| NIST SP 800-34 Rev. 1 (May 2010, errata 2010-11-11) | <https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-34r1.pdf> | 200 | md5 `4086cebd881a90b19d97204c27f47130`, 149 PDF pages |
| NIST SP 800-53 Rev. 5 (Sept 2020, updates to 2020-12-10) | <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf> | 200 | md5 `bb4a2bba565b3200477ead5fe69fcb77`, 492 PDF pages; CP family printed pp. 115–130 |
| FedRAMP Rev. 5 Security Controls Baseline (xlsx) | <https://raw.githubusercontent.com/FedRAMP/docs-legacy/main/overrides/assets/LEGACY%20FedRAMP_Security_Controls_Baseline.xlsx> | 200 | md5 `27014085d5289f1f0674bcf27f9e5dc1`; COVERSHEET carries "LEGACY NOTICE June 23, 2026" |
| FedRAMP SSP Appendix G ISCP Template (docx, template rev. 5.1 of 06/17/2026) | <https://raw.githubusercontent.com/FedRAMP/docs-legacy/main/overrides/assets/LEGACY%20SSP-Appendix-G-Information-System-Contingency-Plan-(ISCP)-Template.docx> | 200 | md5 `59ac4c888f51bb5359903d47839c125d` |
| FedRAMP Consolidated Rules for 2026 (JSON, version 2026.07.14.01) | <https://raw.githubusercontent.com/FedRAMP/rules/main/fedramp-consolidated-rules.json> | 200 | md5 `3f26f847c427edc74471b5f0f6fac5f9`; the site at <https://www.fedramp.gov/2026/sources/> names this file as "the source of truth for structured FedRAMP rules" |
| DoDI 8510.01, March 12, 2014, Incorporating Change 3, December 29, 2020 | <https://www.doncio.navy.mil/Filehandler.ashx?id=18360> | 200 only with a browser `User-Agent`; the default `curl` agent gets an HTML "Request Rejected" page | md5 `c46720388f5459e940fd92796884e4e1`, 47 PDF pages |
| DoDI 8510.01, 2022 reissue | <https://www.esd.whs.mil/Portals/54/Documents/DD/issuances/dodi/851001p.pdf> and <https://dodcio.defense.gov/Portals/0/Documents/Library/DoDI-8510.01.pdf> | 403 to both agents on both hosts | none: INACCESSIBLE |
| CNSSI 1253 (listing: "Security Categorization and Control Selection for National Security Systems", Release Date 08/01/2022, File Size 3655340) | <https://www.cnss.gov/CNSS/issuances/Instructions.cfm> | Listing 200 only with TLS verification disabled; the listing's `openDoc.cfm` link for CNSSI 1253 returns 302 to `/cnss/error_page.cfm?EC=09`; attachments 3, 4, 4.1 and 4.2 are marked FOUO and require Federal/DoD PKI, PIV or CAC login | none: INACCESSIBLE |

**Page arithmetic for SP 800-34.** Body printed page *N* is PDF page *N* + 14 (§3.5.2 on
printed 28 is PDF page 42; §4.2.2 on printed 37 is PDF page 51). Appendix A.1-*k* is PDF
page 72 + *k*, A.2-*k* is 86 + *k*, A.3-*k* is 102 + *k*. Appendix B-1 is PDF page 119,
Appendix E-1 is PDF page 131. Cite the printed page, and link the PDF page as the issues do
(`...800-34r1.pdf#page=42`).

**Page arithmetic for SP 800-53 Rev. 5.** Printed page *N* is PDF page *N* + 27 (CP-1 on
printed 115 is PDF page 142).

**Table numbering in SP 800-34 is internally inconsistent; cite the body caption and say so.**
The List of Tables (printed viii) reads "Table 3-5: ISCP TT&E Activities ... 30" and
"Table 3-6: Sample Record of Changes ... 32". The body captions read "Table 3-5: Contingency
Strategy Budget Planning Template" (printed 25), "Table 3-6: ISCP TT&E Activities" (printed
30) and "Table 3-7: Sample Record of Changes" (printed 32), and the sentences that introduce
them carry an unresolved field code ("depicted in Table ,"). Issue #1 cites the body caption
(3-7); issue #4 cites the List of Tables number (3-5) for the TT&E table. Use the body
caption with the printed page, and note the discrepancy once in the report.

**Extraction.** Use a PDF text extractor that preserves page boundaries (PyMuPDF), dump one
string per page, and grep the dump for every quote you put in a row before you finish. A
quote that does not grep is a fabricated quote and invalidates the row. Ellipses mark
omitted words and nothing else; NIST's own typos (the doubled "that that" in §3.5.2) are
kept as printed.

## 4. Checklist A: NIST SP 800-34 Rev. 1

Every identifier below is one row in the report. The quote column is what the source says;
the auditor's job is to find the repository sentence that answers it or to say there is
none. Where the requirement is a list, the row is PASS only if every listed element is
evidenced, PARTIAL if some are, and the missing elements are named.

### A.1 The seven-step process (Chapter 3)

| ID | Section · printed page | What the source requires (verbatim) |
|---|---|---|
| N34-3.1 | §3.1 Develop the Contingency Planning Policy Statement · 14 | "the contingency plan must be based on a clearly defined policy. The contingency planning policy statement should define the organization's overall contingency objectives and establish the organizational framework and responsibilities for system contingency planning." Key policy elements: "Roles and responsibilities; Scope ... subject to contingency planning; Resource requirements; Training requirements; Exercise and testing schedules; Plan maintenance schedule; and Minimum frequency of backups and storage of backup media." |
| N34-3.2 | §3.2 Conduct the Business Impact Analysis · 15–16 | "The BIA purpose is to correlate the system with the critical mission/business processes and services provided, and based on that information, characterize the consequences of a disruption." Three steps: "1. Determine mission/business processes and recovery criticality ... 2. Identify resource requirements ... 3. Identify recovery priorities for system resources." |
| N34-3.2.1a | §3.2.1 · 16 | "FIPS 199 requires organizations to categorize their information systems as low impact, moderate impact, or high impact for the security objectives of confidentiality, integrity, and availability (RMF Step 1). The FIPS 199 category for the availability security objective serves as a basis of the BIA." The plan must state its availability impact level; if it does not, this row is REFUTED and every "high-impact" template row below is audited against A.3 as the superset. |
| N34-3.2.1b | §3.2.1 · 17 | MTD: "The MTD represents the total amount of time the system owner/authorizing official is willing to accept for a mission/business process outage or disruption and includes all impact considerations." RTO: "RTO defines the maximum amount of time that a system resource can remain unavailable before there is an unacceptable impact on other system resources, supported mission/business processes, and the MTD." RPO: "The RPO represents the point in time, prior to a disruption or system outage, to which mission/business process data can be recovered ... Unlike RTO, RPO is not considered as part of MTD." Check the plan's definitions against these, not against the plan's own paraphrase. |
| N34-3.2.1c | §3.2.1 · 17 | "When it is not feasible to immediately meet the RTO and the MTD is inflexible, a Plan of Action and Milestone should be initiated to document the situation and plan for its mitigation." Look for what the plan does when a drill misses the RTO. |
| N34-3.2.2 | §3.2.2 Identify Resource Requirements · 19 | "the ISCP Coordinator should ensure that the complete information system resources are identified." Table 3-1 columns: "System Resource/Component", "Platform/OS/Version (as applicable)", "Description". |
| N34-3.2.3 | §3.2.3 Identify System Resource Recovery Priorities · 19 | "Developing recovery priorities is the last step of the BIA process. ... The result is an information system recovery priority hierarchy." |
| N34-3.3 | §3.3 Identify Preventive Controls · 19–20 | "Where feasible and cost-effective, preventive methods are preferable to actions that may be necessary to recover the system after a disruption." The list includes "Offsite storage of backup media, non electronic records, and system documentation" and "Technical security controls, such as cryptographic key management". |
| N34-3.4.1 | §3.4.1 Backup and Recovery · 20–21 | "The methods and strategies should address disruption impacts and allowable downtimes identified in the BIA". Table 3-2, High row: "Backup: Mirrored systems and disc replication Strategy: Hot site". |
| N34-3.4.2 | §3.4.2 Backup Methods and Offsite Storage · 21 | "Policies should specify the minimum frequency and scope of backups (e.g., daily or weekly, incremental or full) based on data criticality and the frequency that new information is introduced. Data backup policies should designate the location of stored data, file-naming conventions, media rotation frequency, and method for transporting data offsite." Footnote 25: "Backup tapes should be tested regularly to ensure that data are being stored correctly and that the files may be retrieved without errors or lost data." |
| N34-3.4.3a | §3.4.3 Alternate Sites · 22 | "for all FIPS 199 moderate- or high-impact systems, the plan should include a strategy to recover and perform system operations at an alternate facility for an extended period." and "the fixed site should be in a geographic area that is unlikely to be negatively affected by the same hazard as the organization's primary site." |
| N34-3.4.3b | §3.4.3 · 23–24 | "An MOU or an SLA for an alternate site should be developed specific to the organization's needs and the partner organization's capabilities. The legal department of each party must review and approve the agreement." The agreement elements list runs from "Contract/agreement duration" to "Other technical requirements, as applicable". For a cloud region pair this is the provider agreement; the row asks whether the plan identifies it. |
| N34-3.4.4 | §3.4.4 Equipment Replacement · 24–25 | "Regardless of the strategy selected, detailed lists of equipment needs and specifications should be maintained within the contingency plan." |
| N34-3.4.5 | §3.4.5 Cost Considerations · 25 | "The organization should perform a cost-benefit analysis to identify the optimum contingency strategy." |
| N34-3.4.6 | §3.4.6 Roles and Responsibilities · 26–27 | "the ISCP Coordinator must designate appropriate teams to implement the strategy. Each team should be trained and ready to respond in the event of a disruptive situation requiring plan activation." "Teams should be sufficient in size to remain viable if some members are unavailable to respond or alternate team members may be designated." "Team leaders should have a designated alternate to act as the leader if the primary leader is unavailable." "A senior management official, such as the CIO, has the ultimate authority to activate the plan and to make decisions regarding spending levels, acceptable risk, and interagency coordination." |
| N34-3.5 | §3.5 Plan Testing, Training, and Exercises · 27 | "An ISCP should be maintained in a state of readiness, which includes having personnel trained to fulfill their roles and responsibilities within the plan, having plans exercised to validate their content, and having systems and system components tested to ensure their operability in the environment specified in the ISCP." "Organizations should conduct TT&E events periodically, following organizational or system changes, or the issuance of new TT&E guidance, or as otherwise needed." "For each TT&E activity conducted, results are documented in an after-action report, and Lessons Learned corrective actions are captured for updating information in the ISCP." |
| N34-3.5.1 | §3.5.1 Testing · 27–28 | "Each information system component should be tested to confirm the accuracy of individual recovery procedures. The following areas should be addressed in a contingency plan test, as applicable: Notification procedures; System recovery on an alternate platform from backup media; Internal and external connectivity; System performance using alternate equipment; Restoration of normal operations; and Other plan testing (where coordination is identified, i.e., COOP, BCP)." "the ISCP Coordinator should develop a test plan designed to examine the selected element(s) against explicit test objectives and success criteria." Six areas, six sub-verdicts. |
| N34-3.5.2 | §3.5.2 Training · 28 | "Training should be provided at least annually. Personnel newly appointed to ISCP roles should receive training shortly thereafter. Ultimately, ISCP personnel should be trained to the extent that that they are able to execute their respective recovery roles and responsibilities without aid of the actual ISCP document." Elements: "Purpose of the plan; Cross-team coordination and communication; Reporting procedures; Security requirements; Team-specific processes ...; and Individual responsibilities". KNOWN #4. |
| N34-3.5.3 | §3.5.3 Exercises · 29 | "Tabletop exercises are discussion-based exercises where personnel meet in a classroom setting or in breakout groups to discuss their roles during an emergency" and "Functional exercises allow personnel to validate their operational readiness for emergencies by performing their duties in a simulated operational environment." The plan must say which exercise types it runs. |
| N34-3.5.4 | §3.5.4 TT&E Program Summary · 30–31 | "For high-impact systems, a full-scale functional exercise at an organization-defined frequency should be conducted. The full-scale functional exercise should include a system failover to the alternate location." Body-caption Table 3-6 "ISCP TT&E Activities", High Impact = Yes for: ISCP Training (CP-3); Instruction (CP-3) "includes refresher training. (For a high-impact system, incorporate simulated events.)"; Contingency Plan Test / Exercise (CP-4); Functional Exercise (CP-4); Full-Scale Functional Exercise (CP-4) "Simulation prompting a full recovery and reconstitution of the information system to a known state"; Alternate Processing Site Recovery (CP-4, CP-7) "the alternate site should be fully configured as defined in the plan"; System Backup (CP-9) "Test backup information to verify media reliability and information integrity." One sub-verdict per table row. |
| N34-3.6a | §3.6 Plan Maintenance · 31 | "the plan should be reviewed for accuracy and completeness at an organization-defined frequency or whenever significant changes occur to any element of the plan. Certain elements, such as contact lists, will require more frequent reviews. The plans for moderate- or high-impact systems should be reviewed more often." KNOWN G3 / T12. |
| N34-3.6b | §3.6 · 31–32 | "At a minimum, plan reviews should focus on the following elements: Operational requirements; Security requirements; Technical procedures; Hardware, software, and other equipment (types, specifications, and amount); Names and contact information of team members; Names and contact information of vendors, including alternate and offsite vendor POCs; Alternate and offsite facility requirements; and Vital records (electronic and hardcopy)." |
| N34-3.6c | §3.6 · 32 | "Because the ISCP contains potentially sensitive operational and personnel information, its distribution should be marked accordingly and controlled. ... A copy should also be stored at the alternate site and with the backup media. ... The ISCP Coordinator should maintain a record of copies of the plan and to whom they were distributed." `checklists/pre-failover-precheck.md` §E ("Runbooks accessible from outside Ashburn") is the nearest artefact; decide whether it meets "stored at the alternate site". |
| N34-3.6d | §3.6, body-caption Table 3-7 · 32 | "The ISCP Coordinator should record plan modifications using a record of changes, which lists the page number, change comment, and date of change. The record of changes, depicted in Table , should be integrated into the plan as discussed in Section 4.1." Columns: "Page #", "Change Comment", "Date of Change", "Signature". "Strict version control must be maintained by requesting old plans or plan pages to be returned to the ISCP Coordinator in exchange for the new plan or plan pages." KNOWN #1. |
| N34-3.6e | §3.6 · 32–33 | Supporting information the Coordinator "should evaluate ... to ensure that the information is current": "Alternate site contract, including testing times; Offsite storage contract; Software licenses; MOUs or vendor SLAs; Hardware and software requirements; System interconnection agreements; Security requirements; Recovery strategy; Contingency policies; Training and awareness materials; Testing scope; and Other plans, e.g., COOP, BCP." "When a significant change occurs, the BIA should be updated with the new information to identify new contingency requirements or priorities." |

### A.2 Plan components (Chapter 4)

| ID | Section · printed page | What the source requires (verbatim) |
|---|---|---|
| N34-4.1a | §4.1 Supporting Information · 35 | Introduction: "Background. This subsection establishes the reason for developing the ISCP and defines the plan objectives." "Scope. The scope identifies the FIPS 199 impact level and associated RTOs as well as the alternate site and data storage capabilities (as applicable)." "Assumptions. This section includes the list of assumptions that were used in developing the ISCP as well as a list of situations that are not applicable." Three sub-verdicts. |
| N34-4.1b | §4.1 · 35 | Concept of operations: "System description. ... The description should include the information system architecture, location(s), and any other important technical considerations. An input/output (I/O) diagram and system architecture diagram, including security devices (e.g., firewalls, internal and external connections) are useful." "Overview of three phases. The ISCP recovery is implemented in three phases: (1) Activation and Notification, (2) Recovery, and (3) Reconstitution." "Roles and responsibilities. ... Teams and team members should be designated for specific response and recovery roles during contingency plan activation." Three sub-verdicts. |
| N34-4.2.1 | §4.2.1 Activation Criteria and Procedure · 36 | "Activation criteria for system outages or disruptions are unique for each organization and should be stated in the contingency planning policy. Criteria may be based on: Extent of any damage to the system (e.g., physical, operational, or cost); Criticality of the system to the organization's mission ...; and Expected duration of the outage lasting longer than the RTO." Footnote 31: "Only one individual should have this authority, and a successor should be clearly identified to assume that responsibility if necessary." |
| N34-4.2.2a | §4.2.2 Notification Procedures · 36–37 | "Notification procedures should be documented in the plan for both types of situation. The procedures should describe the methods used to notify recovery personnel during business and non business hours." (the two types are outages with and without prior notice) "The notification strategy should define procedures to be followed in the event that specific personnel cannot be contacted." "A common manual notification method is a call tree. ... The call tree should account for primary and alternate contact methods and should discuss procedures to be followed if an individual cannot be contacted." (Figure 4-2, printed 37.) |
| N34-4.2.2b | §4.2.2 · 37 | "Personnel to be notified should be clearly identified in the contact lists appended to the plan. This list should identify personnel by their team position, name, and contact information (e.g., home, work, cell phone, email addresses, and home addresses)." KNOWN #3. The evidence is now `checklists/contact-roster.md` (call tree §1, roster §2, unreachable procedure §3, external POCs §5); `dr-authority-matrix.md` no longer carries a table of its own and points there instead. Audit that file, and check its columns against the quote - team position, name, and contact information including home, work, cell, email and home address - before deciding between PASS, PARTIAL and CLOSED #3. |
| N34-4.2.2c | §4.2.2 · 38 | "Notifications also should be sent to POCs of external organizations or interconnected system partners that may be adversely affected ... For each system interconnection with an external organization, a POC should be identified. These POCs should be listed in an appendix to the plan." Notification content: "Nature of the outage or disruption ...; Any known outage estimates; Response and recovery details; Where and when to convene ...; Instructions to prepare for relocation ...; and Instructions to complete notifications using the call tree". |
| N34-4.2.3 | §4.2.3 Outage Assessment · 38–39 | Minimum areas: "Cause of the outage or disruption; Potential for additional disruptions or damage; Status of physical infrastructure ...; Inventory and functional status of system equipment ...; Type of damage to system equipment or data ...; Items to be replaced ...; and Estimated time to restore normal services." "Personnel with outage assessment responsibilities should understand and be able to perform these procedures in the event the plan is inaccessible during the situation." |
| N34-4.3.1 | §4.3.1 Sequence of Recovery Activities · 39 | "recovery procedures should reflect system priorities identified in the BIA. The sequence of activities should reflect the system's MTD to avoid significant impacts to related systems. Procedures should be written in a stepwise, sequential format". Escalation steps for: "An action is not completed within the expected time frame; A key step has been completed; Item(s) must be procured; and Other system-specific concerns exist." |
| N34-4.3.2 | §4.3.2 Recovery Procedures · 39–40 | "the ISCP should provide detailed procedures to restore the information system or components to a known state." Actions typically addressed: "Obtaining authorization to access damaged facilities ...; Notifying internal and external business partners ...; Obtaining necessary office supplies and work space; Obtaining and installing necessary hardware components; Obtaining and loading backup media; Restoring critical operating system and application software; Restoring system data to a known state; Testing system functionality including security controls; Connecting system to network or other external systems; and Operating alternate equipment successfully." "no procedural steps should be assumed or omitted. A checklist format is useful". Ten sub-verdicts; several will be NOT APPLICABLE for a cloud region pair and the row must say why with the plan's own scope sentence. |
| N34-4.3.3 | §4.3.3 Recovery Escalation and Notification · 40–41 | "Effective escalation and notification procedures should define and describe the events, thresholds, or other types of triggers that are necessary for additional action. Actions would include additional notifications for more recovery staff, messages and status updates to leadership, and notices for additional resources." |
| N34-4.4a | §4.4 Reconstitution Phase · 41 | Validation: "Concurrent Processing. ... running a system at two separate locations concurrently until there is a level of assurance that the recovered system is operating correctly and securely." (footnote 33: "information systems are not required to have concurrent processing capabilities") "Validation Data Testing. ... ensure that data files or databases have been recovered completely and are current to the last available backup." "Validation Functionality Testing. ... verifying that all system functionality has been tested, and the system is ready to return to normal operations." |
| N34-4.4b | §4.4 · 41 | "At the successful completion of the validation testing, ISCP personnel will be prepared to declare that reconstitution efforts are complete and that the system is operating normally. This declaration may be made in a recovery/reconstitution log or other documentation of reconstitution activities. The ISCP Coordinator, in coordination with the Information System Owner, ISSO, SAISO and with the concurrence of the Authorizing Official, must determine if the system has undergone significant change and will require reassessment and reauthorization." |
| N34-4.4c | §4.4 · 41–42 | Deactivation: "Notifications. Upon return to normal operations, users should be notified ... Cleanup. ... Offsite Data Storage. ... If offsite data storage is used, procedures should be documented for returning retrieved backup or installation media ... Data Backup. As soon as reasonable following reconstitution, the system should be fully backed up ... Event Documentation. All recovery and reconstitution events should be well documented ... An after-action report with lessons learned should be documented and included for updating the ISCP." "Once all activities and steps have been completed and documentation has been updated, the ISCP can be formally deactivated. An announcement with the declaration should be sent to all business and technical contacts." Six sub-verdicts. |
| N34-4.5 | §4.5 Plan Appendices · 42 | "Contact information for contingency planning team personnel; Vendor contact information, including offsite storage and alternate site POCs; BIA; Detailed recovery procedures and checklists; Detailed validation testing procedures and checklists; Equipment and system requirements lists ...; Alternate mission/business processing procedures ...; ISCP testing and maintenance procedures; System interconnections ...; and Vendor SLAs, reciprocal agreements with other organizations, and other vital records." Ten sub-verdicts. |

### A.3 NIST's ISCP template outline (Appendix A)

Appendix A carries three templates: A.1 low-impact, A.2 moderate-impact, A.3 high-impact.
They share the outline through 4.3 and differ in §5: A.1 has no Concurrent Processing and
no Offsite Data Storage (5.1–5.8); A.2 has Offsite Data Storage but no Concurrent
Processing (5.1–5.9); A.3 has both (5.1–5.10). Audit against the template for the plan's
stated availability impact level. If the plan states none (row N34-3.2.1a), audit against
A.3 and record that choice. Printed pages below are A.3's; the A.1 and A.2 pages are the
same headings two columns to the left in Appendix A's own tables of contents (printed
A.1-2 and A.2-2).

| ID | Template section · printed page | What the source requires (verbatim) |
|---|---|---|
| N34-A-PA | Plan Approval · A.3-3 (identical text at A.1-3 and A.2-3) | "Provide a statement in accordance with the agency's contingency planning policy to affirm that the ISCP is complete and has been tested sufficiently. The statement should also affirm that the designated authority is responsible for continued maintenance and testing of the ISCP. This statement should be approved and signed by the system designated authority." Sample language: "I further attest that this ISCP for {system name} will be tested at least annually. This plan was last tested on {insert exercise date}". KNOWN #2. |
| N34-A-1 | 1 Introduction · A.3-4 | "This Information System Contingency Plan (ISCP) establishes comprehensive procedures to recover {system name} quickly and effectively following a service disruption." |
| N34-A-1.1 | 1.1 Background · A.3-4 | Objectives: "Maximize the effectiveness of contingency operations through an established plan that consists of the following phases ...; Identify the activities, resources, and procedures ...; Assign responsibilities to designated {organization name} personnel ...; Ensure coordination with other personnel responsible for {organization name} contingency planning strategies. Ensure coordination with external points of contact and vendors". |
| N34-A-1.2 | 1.2 Scope · A.3-4 | "This ISCP has been developed for {system name}, which is classified as a high-impact system, in accordance with Federal Information Processing Standards (FIPS) 199 ... designed to recover {system name} within {RTO hours}. This plan does not address replacement or purchase of new equipment, short-term disruptions lasting less than {RTO hours}, or loss of data at the onsite facility or at the user-desktop levels." |
| N34-A-1.3 | 1.3 Assumptions · A.3-4 to A.3-5 | Includes "Key {system name} personnel have been identified and trained in their emergency response and recovery roles; they are available to activate the {system name} Contingency Plan." and the not-applicable list: "Overall recovery and continuity of mission/business operations. The Business Continuity Plan (BCP) and Continuity of Operations Plan (COOP) address continuity of business operations. Emergency evacuation of personnel. The Occupant Emergency Plan (OEP) addresses employee evacuation." The plan's `docs/01` §1 assumptions table is the candidate; check for the not-applicable list separately. |
| N34-A-2.1 | 2.1 System Description · A.3-5 | "Provide a general description of system architecture and functionality. Indicate the operating environment, physical location, general location of users, and partnerships with external organizations/systems. Include information regarding any other technical considerations that are important for recovery purposes, such as backup procedures." |
| N34-A-2.2 | 2.2 Overview of Three Phases · A.3-5 to A.3-6 | "Activation and Notification Phase – Activation of the ISCP occurs after a disruption or outage that may reasonably extend beyond the RTO established for a system." "Recovery Phase – ... Activities and procedures are written at a level that an appropriately skilled technician can recover the system without intimate system knowledge." "Reconstitution – ... This phase consists of two major activities: validating successful reconstitution and deactivation of the plan." |
| N34-A-2.3 | 2.3 Roles and Responsibilities · A.3-6 | "At a minimum, a role should be established for a system owner or business unit point of contact, a recovery coordinator, and a technical recovery point of contact. Leadership roles should include an ISCP Director, who has overall management responsibility for the plan, and an ISCP Coordinator, who is responsible to oversee recovery and reconstitution progress, initiate any needed escalations or awareness communications, and establish coordination with other recovery and reconstitution teams". Map the plan's DR Commander / DR Coordinator / business owner to these; the mapping must be in the plan, not in the audit. |
| N34-A-3.1 | 3.1 Activation Criteria and Procedure · A.3-6 to A.3-7 | "1. The type of outage indicates {system name} will be down for more than {RTO hours}; 2. The facility housing {system name} is damaged and may not be available within {RTO hours}; and 3. Other criteria, as appropriate." "Establish one or more roles that may activate the plan based on activation criteria." |
| N34-A-3.2 | 3.2 Notification · A.3-7 | "Contact information for appropriate POCs is included in {Contact List Appendix name}." "Notification procedures should include who makes the initial notifications, the sequence in which personnel are notified ..., and the method of notification (e.g., email blast, call tree, automated notification system, etc.)." |
| N34-A-3.3 | 3.3 Outage Assessment · A.3-7 | "This outage assessment is conducted by {name of recovery team}. Assessment results are provided to the ISCP Coordinator". "Procedures should include notation of items that will need to be replaced and estimated time to restore service to normal operations." |
| N34-A-4.1 | 4.1 Sequence of Recovery Activities · A.3-7 | "1. Identify recovery location (if not at original location); 2. Identify required resources to perform recovery procedures; 3. Retrieve backup and system installation media; 4. Recover hardware and operating system (if required); and 5. Recover system from backup and system installation media." |
| N34-A-4.2 | 4.2 Recovery Procedures · A.3-8 | "Recovery procedures are outlined per team and should be executed in the sequence presented ... Teams or persons responsible for each procedure should be identified." |
| N34-A-4.3 | 4.3 Recovery Escalation Notices/Awareness · A.3-8 | "Notifications during recovery include problem escalation to leadership and status awareness to system owners and users. Teams or persons responsible for each escalation/awareness procedure should be identified." (Chapter 4 calls this "Recovery Escalation and Notification", §4.3.3; the template heading differs.) |
| N34-A-5 | 5 Reconstitution · A.3-8 | "A determination must be made on whether the system has undergone significant change and will require reassessment and reauthorization. The phase consists of two major activities: validating successful reconstitution and deactivation of the plan." |
| N34-A-5.1 | 5.1 Concurrent Processing · A.3-8 | "High-impact systems are not required to have concurrent processing as part of the validation effort. If concurrent processing does occur for the system prior to making it operational, procedures should be inserted here." NOT APPLICABLE is available here only with this sentence and a plan statement that concurrent processing is not used. |
| N34-A-5.2 | 5.2 Validation Data Testing · A.3-8 to A.3-9 | "The following procedures will be used to determine that the recovered data is complete and current to the last available backup ... An example of a validation data test for a high-impact system would be to log into the system database and check the audit logs to determine that all transactions and updates are current." |
| N34-A-5.3 | 5.3 Validation Functionality Testing · A.3-9 | "Provide system functionality testing and validation procedures to ensure that the system is operating correctly. ... An example of a functional test for a high-impact system may be logging into the system and running a series of operations as a test or real user". |
| N34-A-5.4 | 5.4 Recovery Declaration · A.3-9 | "Upon successfully completing testing and validation, the {designated authority} will formally declare recovery efforts complete, and that {system name} is in normal operations. {System name} business and technical POCs will be notified of the declaration by the ISCP Coordinator." |
| N34-A-5.5 | 5.5 Notifications (users) · A.3-9 | "Upon return to normal system operations, {system name} users will be notified by {role} using predetermined notification procedures (e.g., email, broadcast message, phone calls, etc.)." |
| N34-A-5.6 | 5.6 Cleanup · A.3-9 | "Cleanup is the process of cleaning up or dismantling any temporary recovery locations, restocking supplies used, returning manuals or other documentation to their original locations, and readying the system for a possible future contingency event." |
| N34-A-5.7 | 5.7 Offsite Data Storage · A.3-9 | "It is important that all backup and installation media used during recovery be returned to the offsite data storage location." For a cloud environment, state what "offsite" is (the plan's Recovery Service and cross-region backup copies) and whether any return step exists. |
| N34-A-5.8 | 5.8 Data Backup · A.3-10 | "As soon as reasonable following recovery, the system should be fully backed up and a new copy of the current operational system stored for future recovery efforts." |
| N34-A-5.9 | 5.9 Event Documentation · A.3-10 | "Activity logs (including recovery steps performed and by whom, the time the steps were initiated and completed, and any problems or concerns encountered while executing activities); Functionality and data testing results; Lessons learned documentation; and After Action Report." "Event documentation procedures should detail responsibilities for development, collection, approval, and maintenance." |
| N34-A-5.10 | 5.10 Deactivation · A.3-10 | "Once all activities have been completed and documentation has been updated, the {designated authority} will formally deactivate the ISCP recovery and reconstitution effort. Notification of this declaration will be provided to all business and technical POCs." |
| N34-A-AppA | Appendix A Personnel Contact List · A.3-11 | "Provide contact information for each person with a role or responsibility for activation or implementation of the ISCP, or coordination with the ISCP. For each person listed, at least one office and one non-office contact number is recommended." Roles in the sample: ISCP Director and alternate, ISCP Coordinator and alternate, team leads, team members. KNOWN #3. |
| N34-A-AppB | Appendix B Vendor Contact List · A.3-11 | "Contact information for all key maintenance or support vendors should be included in this appendix. Contact information, such as emergency phone numbers, contact names, contract numbers, and contractual response and onsite times should be included." The authority matrix's "Oracle Support (CSI + severity-1 path)" row is the candidate. |
| N34-A-AppC | Appendix C Detailed Recovery Procedures · A.3-11 to A.3-12 | "Keystroke-level recovery steps; System installation instructions ...; Required configuration settings or changes; Recovery of data from tape and audit logs; and Other system recovery procedures". |
| N34-A-AppD | Appendix D Alternate Processing Procedures · A.3-12 | "identify any alternate manual or technical processing procedures available that allow the business unit to continue some processing of information that would normally be done by the affected system." |
| N34-A-AppE | Appendix E System Validation Test Plan · A.3-12 | "system acceptance procedures that are performed after the system has been recovered and prior to putting the system into full operation and returned to users." Table columns: "Procedure", "Expected Results", "Actual Results", "Successful?", "Performed by". |
| N34-A-AppF | Appendix F Alternate Storage, Site, and Telecommunications · A.3-13 to A.3-14 | "Alternate storage, site, and telecommunications information is required for high-impact systems". Alternate Storage items include "City and state of alternate storage facility, and distance from primary facility" and "Any potential accessibility problems to the alternate storage site in the event of a widespread disruption or disaster". Alternate Processing Site items include "SLAs or other agreements of use of alternate processing site". Alternate Telecommunications items include "Contracted capacity of alternate telecommunications" and "Information on alternate telecommunications vendor contingency plans". Three sub-verdicts (storage, site, telecommunications). |
| N34-A-AppG | Appendix G Diagrams (System and Input/Output) · A.3-14 | "Include any system architecture, input/output, or other technical or logical diagrams that may be useful in recovering the system. Diagrams may also identify information about interconnection with other systems." |
| N34-A-AppH | Appendix H Hardware and Software Inventory · A.3-14 | "Inventory information should include type of server or hardware on which the system runs, processors and memory requirements, storage requirements, and any other pertinent details. The software inventory should identify the operating system (including service pack or version levels, and any other applications necessary to operate the system, such as database software)." |
| N34-A-AppI | Appendix I Interconnections Table · A.3-14 | "information on other systems that directly interconnect or exchange information with the system. Interconnection information should include the type of connection, information transferred, and contact person for that system." |
| N34-A-AppJ | Appendix J Test and Maintenance Schedule · A.3-14 to A.3-15 | "All ISCPs should be reviewed and tested at the organization defined frequency (e.g. yearly) or whenever there is a significant change to the system." "The full functional test should include all ISCP points of contact and be facilitated by an outside or impartial observer." "It is highly recommended that several functional tests be conducted and evaluated prior to conducting a full functional (failover) test." Sample schedule columns: "Step", "Date Due by", "Responsible Party", "Date Scheduled", "Date Held". |
| N34-A-AppK | Appendix K Associated Plans and Procedures · A.3-15 | "ISCPs for other systems that either interconnect or support the system should be identified in this appendix. The most current version of the ISCP, location of ISCP, and primary point of contact (such as the ISCP Coordinator) should be noted." |
| N34-A-AppL | Appendix L Business Impact Analysis · A.3-16 | "The Business Impact Analysis results should be included in this appendix." Appendix B (printed B-1 to B-2) gives the BIA template: overview, system description, "3.1 Determine Process and System Criticality", "3.1.1 Identify Outage Impacts and Estimated Downtime" with impact categories and values. |
| N34-A-AppM | Appendix M Document Change Page · A.3-16 | "Modifications made to this plan since the last printing are as follows:" Record of Changes columns "Page No.", "Change Comment", "Date of Change", "Signature". KNOWN #1. |

## 5. Checklist B: NIST SP 800-53 Rev. 5, CP family

Printed pages 115–130. One row per identifier, including enhancements and withdrawals. The
control statements are quoted here as read; the auditor still greps them. Organization-defined
parameters are audited twice: once for whether the plan *defines* the value, once for whether
the plan *meets* it. A plan that never states a frequency fails the first test regardless of
what it does.

| ID | Printed page | Control statement (verbatim, statement parts only) |
|---|---|---|
| CP-1 | 115 | "a. Develop, document, and disseminate to [Assignment: organization-defined personnel or roles]: 1. [Selection (one or more): Organization-level; Mission/business process-level; System-level] contingency planning policy that: (a) Addresses purpose, scope, roles, responsibilities, management commitment, coordination among organizational entities, and compliance; and (b) Is consistent with applicable laws ...; and 2. Procedures to facilitate the implementation of the contingency planning policy and the associated contingency planning controls; b. Designate an [Assignment: organization-defined official] to manage the development, documentation, and dissemination of the contingency planning policy and procedures; and c. Review and update the current contingency planning: 1. Policy [Assignment: organization-defined frequency] and following [Assignment: organization-defined events]; and 2. Procedures [Assignment: organization-defined frequency] and following [Assignment: organization-defined events]." Discussion: "Simply restating controls does not constitute an organizational policy or procedure." |
| CP-2 a.1–a.7 | 116 | "a. Develop a contingency plan for the system that: 1. Identifies essential mission and business functions and associated contingency requirements; 2. Provides recovery objectives, restoration priorities, and metrics; 3. Addresses contingency roles, responsibilities, assigned individuals with contact information; 4. Addresses maintaining essential mission and business functions despite a system disruption, compromise, or failure; 5. Addresses eventual, full system restoration without deterioration of the controls originally planned and implemented; 6. Addresses the sharing of contingency information; and 7. Is reviewed and approved by [Assignment: organization-defined personnel or roles];" Seven sub-verdicts. a.3 is KNOWN #3; a.7 is KNOWN #2. |
| CP-2 b–h | 116 | "b. Distribute copies of the contingency plan to [Assignment: organization-defined key contingency personnel (identified by name and/or by role) and organizational elements]; c. Coordinate contingency planning activities with incident handling activities; d. Review the contingency plan for the system [Assignment: organization-defined frequency]; e. Update the contingency plan to address changes to the organization, system, or environment of operation and problems encountered during contingency plan implementation, execution, or testing; f. Communicate contingency plan changes to [Assignment: ...]; g. Incorporate lessons learned from contingency plan testing, training, or actual contingency activities into contingency testing and training; and h. Protect the contingency plan from unauthorized disclosure and modification." Seven sub-verdicts. d is KNOWN G3. |
| CP-2(1) | 117 | "Coordinate contingency plan development with organizational elements responsible for related plans." Discussion names "Business Continuity Plans, Disaster Recovery Plans, Critical Infrastructure Plans, Continuity of Operations Plans, Crisis Communications Plans, Insider Threat Implementation Plans, Data Breach Response Plans, Cyber Incident Response Plans, Breach Response Plans, and Occupant Emergency Plans." |
| CP-2(2) | 117 | "Conduct capacity planning so that necessary capacity for information processing, telecommunications, and environmental support exists during contingency operations." |
| CP-2(3) | 117 | "Plan for the resumption of [Selection: all; essential] mission and business functions within [Assignment: organization-defined time period] of contingency plan activation." |
| CP-2(4) | 117 | "[Withdrawn: Incorporated into CP-2(3).]" NOT APPLICABLE. |
| CP-2(5) | 117 | "Plan for the continuance of [Selection: all; essential] mission and business functions with minimal or no loss of operational continuity and sustains that continuity until full system restoration at primary processing and/or storage sites." |
| CP-2(6) | 117–118 | "Plan for the transfer of [Selection: all; essential] mission and business functions to alternate processing and/or storage sites with minimal or no loss of operational continuity and sustain that continuity through system restoration to primary processing and/or storage sites." |
| CP-2(7) | 118 | "Coordinate the contingency plan with the contingency plans of external service providers to ensure that contingency requirements can be satisfied." For this plan the external service provider is Oracle Cloud Infrastructure. |
| CP-2(8) | 118 | "Identify critical system assets supporting [Selection: all; essential] mission and business functions." |
| CP-3 | 118–119 | "a. Provide contingency training to system users consistent with assigned roles and responsibilities: 1. Within [Assignment: organization-defined time period] of assuming a contingency role or responsibility; 2. When required by system changes; and 3. [Assignment: organization-defined frequency] thereafter; and b. Review and update contingency training content [Assignment: organization-defined frequency] and following [Assignment: organization-defined events]." Discussion: "At the discretion of the organization, participation in a contingency plan test or exercise, including lessons learned sessions subsequent to the test or exercise, may satisfy contingency plan training requirements." KNOWN #4; the discussion sentence is the strongest argument the repo has and the row must say whether the plan invokes it. |
| CP-3(1) | 119 | "Incorporate simulated events into contingency training to facilitate effective response by personnel in crisis situations." |
| CP-3(2) | 119 | "Employ mechanisms used in operations to provide a more thorough and realistic contingency training environment." |
| CP-4 | 119–120 | "a. Test the contingency plan for the system [Assignment: organization-defined frequency] using the following tests to determine the effectiveness of the plan and the readiness to execute the plan: [Assignment: organization-defined tests]. b. Review the contingency plan test results; and c. Initiate corrective actions, if needed." |
| CP-4(1) | 120 | "Coordinate contingency plan testing with organizational elements responsible for related plans." |
| CP-4(2) | 120 | "Test the contingency plan at the alternate processing site: (a) To familiarize contingency personnel with the facility and available resources; and (b) To evaluate the capabilities of the alternate processing site to support contingency operations." |
| CP-4(3) | 120 | "Test the contingency plan using [Assignment: organization-defined automated mechanisms]." |
| CP-4(4) | 120–121 | "Include a full recovery and reconstitution of the system to a known state as part of contingency plan testing." |
| CP-4(5) | 121 | "Employ [Assignment: organization-defined mechanisms] to [Assignment: organization-defined system or system component] to disrupt and adversely affect the system or system component." `runbooks/RB-04-dr-drill.md` §4 "Inject a surprise" is the candidate. |
| CP-5 | 121 | "[Withdrawn: Incorporated into CP-2.]" NOT APPLICABLE. |
| CP-6 | 121 | "a. Establish an alternate storage site, including necessary agreements to permit the storage and retrieval of system backup information; and b. Ensure that the alternate storage site provides controls equivalent to that of the primary site." Discussion: "Geographically distributed architectures that support contingency requirements may be considered alternate storage sites." |
| CP-6(1) | 121–122 | "Identify an alternate storage site that is sufficiently separated from the primary storage site to reduce susceptibility to the same threats." |
| CP-6(2) | 122 | "Configure the alternate storage site to facilitate recovery operations in accordance with recovery time and recovery point objectives." |
| CP-6(3) | 122 | "Identify potential accessibility problems to the alternate storage site in the event of an area-wide disruption or disaster and outline explicit mitigation actions." |
| CP-7 | 122–123 | "a. Establish an alternate processing site, including necessary agreements to permit the transfer and resumption of [Assignment: organization-defined system operations] for essential mission and business functions within [Assignment: organization-defined time period consistent with recovery time and recovery point objectives] when the primary processing capabilities are unavailable; b. Make available at the alternate processing site, the equipment and supplies required to transfer and resume operations or put contracts in place to support delivery to the site within the organization-defined time period for transfer and resumption; and c. Provide controls at the alternate processing site that are equivalent to those at the primary site." Discussion: "The alternate processing capability may be addressed using a physical processing site or other alternatives, such as failover to a cloud-based service provider". |
| CP-7(1) | 123 | "Identify an alternate processing site that is sufficiently separated from the primary processing site to reduce susceptibility to the same threats." |
| CP-7(2) | 123 | "Identify potential accessibility problems to alternate processing sites in the event of an area-wide disruption or disaster and outlines explicit mitigation actions." |
| CP-7(3) | 123 | "Develop alternate processing site agreements that contain priority-of-service provisions in accordance with availability requirements (including recovery time objectives)." |
| CP-7(4) | 123 | "Prepare the alternate processing site so that the site can serve as the operational site supporting essential mission and business functions." |
| CP-7(5) | 123 | "[Withdrawn: Incorporated into CP-7.]" NOT APPLICABLE. |
| CP-7(6) | 123–124 | "Plan and prepare for circumstances that preclude returning to the primary processing site." `runbooks/RB-03-failback.md` assumes return; the row asks what the plan says if Ashburn never comes back. |
| CP-8 | 124 | "Establish alternate telecommunications services, including necessary agreements to permit the resumption of [Assignment: organization-defined system operations] for essential mission and business functions within [Assignment: organization-defined time period] when the primary telecommunications capabilities are unavailable at either the primary or alternate processing or storage sites." `docs/01-architecture.md` §1 assumption A6 (DRG + Remote Peering Connection, "No bandwidth guarantee or SLA for the peering link was verified") is the candidate and probably the finding. |
| CP-8(1) | 124 | "(a) Develop primary and alternate telecommunications service agreements that contain priority-of-service provisions in accordance with availability requirements (including recovery time objectives); and (b) Request Telecommunications Service Priority for all telecommunications services used for national security emergency preparedness if the primary and/or alternate telecommunications services are provided by a common carrier." |
| CP-8(2) | 124 | "Obtain alternate telecommunications services to reduce the likelihood of sharing a single point of failure with primary telecommunications services." |
| CP-8(3) | 125 | "Obtain alternate telecommunications services from providers that are separated from primary service providers to reduce susceptibility to the same threats." |
| CP-8(4) | 125 | "(a) Require primary and alternate telecommunications service providers to have contingency plans; (b) Review provider contingency plans to ensure that the plans meet organizational contingency requirements; and (c) Obtain evidence of contingency testing and training by providers [Assignment: organization-defined frequency]." |
| CP-8(5) | 125 | "Test alternate telecommunication services [Assignment: organization-defined frequency]." |
| CP-9 | 125–126 | "a. Conduct backups of user-level information contained in [Assignment: organization-defined system components] [Assignment: organization-defined frequency consistent with recovery time and recovery point objectives]; b. Conduct backups of system-level information contained in the system [Assignment: ...]; c. Conduct backups of system documentation, including security- and privacy-related documentation [Assignment: ...]; and d. Protect the confidentiality, integrity, and availability of backup information." Four sub-verdicts; c is the one plans forget. |
| CP-9(1) | 126 | "Test backup information [Assignment: organization-defined frequency] to verify media reliability and information integrity." |
| CP-9(2) | 126 | "Use a sample of backup information in the restoration of selected system functions as part of contingency plan testing." |
| CP-9(3) | 126–127 | "Store backup copies of [Assignment: organization-defined critical system software and other security-related information] in a separate facility or in a fire rated container that is not collocated with the operational system." |
| CP-9(4) | 127 | "[Withdrawn: Incorporated into CP-9.]" NOT APPLICABLE. |
| CP-9(5) | 127 | "Transfer system backup information to the alternate storage site [Assignment: organization-defined time period and transfer rate consistent with the recovery time and recovery point objectives]." |
| CP-9(6) | 127 | "Conduct system backup by maintaining a redundant secondary system that is not collocated with the primary system and that can be activated without loss of information or disruption to operations." |
| CP-9(7) | 127 | "Enforce dual authorization for the deletion or destruction of [Assignment: organization-defined backup information]." The `--approver` and `--ticket` arguments on `scripts/oci/decommission-dr.sh` and the retention lock in `docs/01` §4.1 are the candidates. |
| CP-9(8) | 127 | "Implement cryptographic mechanisms to prevent unauthorized disclosure and modification of [Assignment: organization-defined backup information]." |
| CP-10 | 128 | "Provide for the recovery and reconstitution of the system to a known state within [Assignment: organization-defined time period consistent with recovery time and recovery point objectives] after a disruption, compromise, or failure." Discussion: "Reconstitution also includes assessments of fully restored system capabilities, reestablishment of continuous monitoring activities, system reauthorization (if required), and activities to prepare the system and organization for future disruptions". |
| CP-10(1) | 128 | "[Withdrawn: Incorporated into CP-4.]" NOT APPLICABLE. |
| CP-10(2) | 128 | "Implement transaction recovery for systems that are transaction-based." |
| CP-10(3) | 128 | "[Withdrawn: Addressed through tailoring.]" NOT APPLICABLE. |
| CP-10(4) | 128 | "Provide the capability to restore system components within [Assignment: organization-defined restoration time periods] from configuration-controlled and integrity-protected information representing a known, operational state for the components." |
| CP-10(5) | 128 | "[Withdrawn: Incorporated into SI-13.]" NOT APPLICABLE. |
| CP-10(6) | 128 | "Protect system components used for recovery and reconstitution." |
| CP-11 | 129 | "Provide the capability to employ [Assignment: organization-defined alternative communications protocols] in support of maintaining continuity of operations." |
| CP-12 | 129 | "When [Assignment: organization-defined conditions] are detected, enter a safe mode of operation with [Assignment: organization-defined restrictions of safe mode of operation]." `runbooks/RB-02-failover.md` §7d ("Stop. Do not start Concurrent Managers.") and the authority matrix's standing decision 5 are the candidates. |
| CP-13 | 129 | "Employ [Assignment: organization-defined alternative or supplemental security mechanisms] for satisfying [Assignment: organization-defined security functions] when the primary means of implementing the security function is unavailable or compromised." `checklists/pre-failover-precheck.md` §D "Break-glass credentials tested within the last 90 days" is the candidate. |

The SP 800-53B baselines were not read for this skill; do not cite them. Baseline
membership is taken from the FedRAMP workbook (Checklist C) for FedRAMP, and is INACCESSIBLE
for national security systems (Checklist E).

## 6. Checklist C: FedRAMP High

FedRAMP has two things in force at once, and the report audits both, labeled.

**C.1 The Rev. 5 High baseline is legacy but still the baseline until 2027-01-01.** The
workbook's COVERSHEET reads: "LEGACY NOTICE June 23, 2026 This is a legacy document that is
being replaced by the FedRAMP Consolidated Rules for 2026: https://fedramp.gov/2026 Use with
extreme caution. Reference the updated rules to understand how changing requirements affect
you." The Important Dates page at <https://www.fedramp.gov/2026/timeline/> reads "January 1,
2027 Mandatory Adoption The Consolidated Rules for 2026 take mandatory effect for all
stakeholders" and "June 11, 2027 End of New Rev5 Certifications". Put both sentences in the
report's access log and date-stamp them; the reader decides which regime applies to them.

The High baseline selects these CP identifiers (sheet "High Baseline", column C); every one
is a row, cross-referenced to its Checklist B row, with the FedRAMP-defined parameter or
requirement quoted from columns G and H where the workbook carries one:

| ID | FedRAMP-defined parameter / requirement (verbatim from the workbook, High sheet) |
|---|---|
| CP-1 | "CP-1 (c) (1) [at least annually] CP-1 (c) (2) [at least annually] [significant changes]" |
| CP-2 | "CP-2 (d) [at least annually]". Requirement: "CSPs must use the FedRAMP Information System Contingency Plan (ISCP) Template (available on the fedramp.gov: https://www.fedramp.gov/assets/resources/templates/SSP-A06-FedRAMP-ISCP-Template.docx)." |
| CP-2(1) | none stated |
| CP-2(2) | none stated |
| CP-2(3) | "CP-2 (3)-1 [all] CP-2 (3)-2 [time period defined in service provider and organization SLA]" |
| CP-2(5) | "CP-2 (5) [essential]" |
| CP-2(8) | none stated |
| CP-3 | "CP-3 (a) (1) [*See Additional Requirements] CP-3 (a) (3) [at least annually] CP-3 (b) [at least annually]". Requirement: "Privileged admins and engineers must take the basic contingency training within 10 days. ... Newly hired critical contingency personnel must take this more in-depth training within 60 days of hire date when the training will have more impact." KNOWN #4, and this is the number #4 does not yet cite. |
| CP-3(1) | none stated |
| CP-4 | "CP-4 (a)-1 [at least annually] CP-4 (a)-2 [functional exercises]". Requirements: "The service provider develops test plans in accordance with NIST Special Publication 800-34 (as amended)." and "The service provider must include the Contingency Plan test results with the security package within the Contingency Plan-designated appendix (Appendix G, Contingency Plan Test Report)." |
| CP-4(1) | none stated |
| CP-4(2) | none stated |
| CP-6, CP-6(1), CP-6(2), CP-6(3) | none stated |
| CP-7 | Requirement: "The service provider defines a time period consistent with the recovery time objectives and business impact analysis." |
| CP-7(1) | Guidance: "The service provider may determine what is considered a sufficient degree of separation between the primary and alternate processing sites, based on the types of threats that are of concern. For one particular type of threat (i.e., hostile cyber attack), the degree of separation between sites will be less relevant." |
| CP-7(2), CP-7(3), CP-7(4) | none stated |
| CP-8 | Requirement: "The service provider defines a time period consistent with the recovery time objectives and business impact analysis." |
| CP-8(1), CP-8(2), CP-8(3) | none stated |
| CP-8(4) | "CP-8 (4) (c) [annually]" |
| CP-9 | "CP-9 (a)-2 [daily incremental; weekly full] CP-9 (b) [daily incremental; weekly full] CP-9 (c) [daily incremental; weekly full]". Requirements: "The service provider maintains at least three backup copies of user-level information (at least one of which is available online) or provides an equivalent alternative." (and the same sentence for system-level information and for "information system documentation including security information"). |
| CP-9(1) | "CP-9 (1) [at least monthly]" |
| CP-9(2), CP-9(3) | none stated |
| CP-9(5) | "CP-9 (5) [time period and transfer rate consistent with the recovery time and recovery point objectives defined in the service provider and organization SLA]." |
| CP-9(8) | "CP-9 (08) [all backup files]". Guidance: "this enhancement requires the use of cryptography which must be compliant with Federal requirements and utilize FIPS validated or NSA approved cryptography (see SC-13.)" |
| CP-10, CP-10(2) | none stated |
| CP-10(4) | "CP-10 (4) [time period consistent with the restoration time-periods defined in the service provider and organization SLA]" |

Thirty-five identifiers. CP-2(6), CP-2(7), CP-3(2), CP-4(3), CP-4(4), CP-4(5), CP-7(6),
CP-8(5), CP-9(6), CP-9(7), CP-10(6), CP-11, CP-12 and CP-13 are not in the High sheet;
their Checklist C rows are NOT APPLICABLE with "not selected in the FedRAMP Rev. 5 High
baseline (workbook sheet 'High Baseline')" as the reason. They stay assessed in Checklist B.

**C.2 FedRAMP's ISCP template.** CP-2's FedRAMP requirement makes the template's outline a
requirement in its own right for a FedRAMP system. The template (revision 5.1, 06/17/2026,
carrying the same legacy notice) is organised: 1 Introduction and Purpose (1.1 Applicable
Laws and Regulations, 1.2 FedRAMP Requirements and Guidance, 1.3 system name and identifier,
1.4 Scope, 1.5 Assumptions); 2 Concept of Operations (2.1 System Description, 2.2 Three
Phases, 2.3 Data Backup Readiness Information, 2.4 Site Readiness Information, 2.5 Roles and
Responsibilities with Plan Distribution and Availability and Line of Succession/Alternates
Roles); 3 Activation and Notification (3.1 Activation Criteria and Procedure with "Table 3.1
Personnel Authorized to Activate the ISCP", 3.2 Notification Instructions, 3.3 Outage
Assessment); 4 Recovery (4.1 Sequence of Recovery Operations, 4.2 Recovery Procedures, 4.3
Recovery Escalation Notices/Awareness); 5 Reconstitution (Data Validation Testing,
Functional Validation Testing, Recovery Declaration, User Notification, Cleanup, Returning
Backup Media, Backing-Up Restored Systems, Event Documentation); 6 Contingency Plan Testing;
appendices A Key Personnel and Team Member Contact List, B Vendor Contact List, C Alternate
Storage Site Information, E System Validation Test Plan, F Contingency Plan Test Report, G
Diagrams, plus inventory, interconnections and associated-plans appendices that reference
the SSP. Sentences the auditor will need:

- 2.3: "The hardware and software components used to create the <Insert CSO Name> backups are noted in Table 2.2 Backup System Components." (rows Software Used · Hardware Used · Frequency · Backup Type · Retention Period) and "<Insert CSO Name> maintains both an online and offline (portable) set of backup copies of the following types of data on site at their primary location: User-level information System-level information Information system documentation including security information."
- 2.5 Plan Distribution and Availability: "The Contingency Plan Coordinator ensures that a copy of the most current version of the Contingency Plan is maintained at CSP Name's facility. This plan has been distributed to all personnel listed in Appendix A".
- 2.5 Line of Succession: "individuals designated as key personnel have been assigned an individual who can assume the key personnel's position if the key personnel is not able to perform their duties."
- 4.1 adds a sixth sequence item absent from SP 800-34's template: "Implementation of transaction recovery for systems that are transaction-based" (CP-10(2)).
- 6: "Contingency Plan operational tests of the <Insert CSO Name> are performed annually. A Contingency Plan Test Report is documented after each annual test."
- Front matter: "Complete for 800-53 Revision 5 the Appendix G: Information System Contingency Plan (ISCP) Revision History." with columns Date · Description · Version · Author (FedRAMP's form of the record of changes; KNOWN #1).

Each template section that has no SP 800-34 twin (1.1, 1.2, 1.3, 2.3, 2.4, Plan Distribution,
Line of Succession, 6, Appendix F Contingency Plan Test Report) is its own row, prefixed
`FR-T-`.

**C.3 The Consolidated Rules for 2026, Key Security Indicators, Recovery Planning (KSI-RPL).**
From the JSON (`KSI` → `RPL`, status "stable", each indicator updated 2026-06-24 "Official
launch of the FedRAMP Consolidated Rules for 2026"):

| ID | Statement (verbatim) | Controls the rule maps to |
|---|---|---|
| KSI-RPL-ABO Aligning Backups with Objectives | "The alignment of machine-based information resource backups with defined recovery objectives is persistently reviewed." | cm-2.3, cp-6, cp-9, cp-10, cp-10.2, si-12 |
| KSI-RPL-ARP Aligning Recovery Plan | "The alignment of recovery plans with defined recovery objectives is persistently reviewed." | cp-2, cp-2.1, cp-2.3, cp-4.1, cp-6, cp-6.1, cp-6.3, cp-7, cp-7.1, cp-7.2, cp-7.3, cp-8, cp-8.1, cp-8.2, cp-10, cp-10.2 |
| KSI-RPL-RRO Reviewing Recovery Objectives | "The desired Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO) are defined and persistently reviewed for alignment with the provider's business needs and capabilities." | cp-2.3, cp-10 |
| KSI-RPL-TRC Testing Recovery Capabilities | "The capability to recover from incidents and contingencies aligned with defined recovery objectives is persistently tested." | cp-2.1, cp-2.3, cp-4, cp-4.1, cp-6, cp-6.1, cp-9.1, cp-10, ir-3, ir-3.2 |

"Persistently" is a defined term in the JSON's `FRD` section; read its definition before
scoring these four rows and quote it in the report. The KSI default artifacts in the JSON
`info.default_artifacts.KSI` list ("Explanation of measures (and their objectives) that
demonstrate the Key Security Indicator ...", "Explanation of the cycle for any measures
that are implemented persistently") are what an assessor will ask for; `docs/04-monitoring.md`
§4 (monthly RPO attestation) and `runbooks/RB-04-dr-drill.md` (quarterly, monthly for Tier 0)
are the candidates. Report FRR rules only if you read them; the skill did not enumerate them.

## 7. Checklist D: DoDI 8510.01

**What was read.** The March 12, 2014 edition incorporating Change 3 of December 29, 2020,
from the Navy-hosted copy. Its own paragraph 6 says "This instruction is available on the
Directives Division Website at https://www.esd.whs.mil/DD/", which returned 403. A 2022
reissue exists (docs/07 says so, citing the same 403); its text was not read, so any
sentence quoted below is from a superseded edition and the report must say so on every
DoDI row. Do not paraphrase the 2022 text from memory.

| ID | Location (2014 ed., Change 3) · PDF page | Requirement (verbatim) | What the repo can evidence |
|---|---|---|---|
| DoDI-3d | Policy ¶3.d · 2 | "All DoD IS and PIT systems must be categorized in accordance with Committee on National Security Systems Instruction (CNSSI) 1253 (Reference (e)), implement a corresponding set of security controls from NIST SP 800-53 (Reference (f)), and use assessment procedures from NIST SP 800-53A (Reference (g)) and DoD-specific assignment values, overlays, implementation guidance, and assessment procedures found on the Knowledge Service". (docs/07 §1a quotes an elided form of this sentence; check its ellipsis against the full text.) | Whether the plan states a CNSSI 1253 categorization and which 800-53 baseline it implements. The KS assignment values are login-gated: INACCESSIBLE for that clause. |
| DoDI-3f | Policy ¶3.f · 3 | "Each DoD IS, DoD partnered system, and PIT system must have an authorizing official (AO) responsible for authorizing the system's operation based on achieving and maintaining an acceptable risk posture." | Whether the plan names the AO role in the reconstitution reauthorization decision (N34-4.4b names the Authorizing Official). |
| DoDI-3i | Policy ¶3.i · 3 | "A plan of action and milestones (POA&M) must be developed and maintained to address known vulnerabilities in the IS or PIT system." | Whether missed RTO/RPO findings (RB-04 §5 defect list; N34-3.2.1c) are tracked as POA&M items. |
| DoDI-3j | Policy ¶3.j · 3 | "Continuous monitoring capabilities will be implemented to the greatest extent possible." | `docs/04-monitoring.md`. |
| DoDI-E6-1d | Enclosure 6 ¶1.d Security Plan · 27 | "Security plans may also include, but are not limited to, a compiled list of system characteristics or qualities required for system registration, key security-related documents such as a risk assessment, privacy impact assessment, system interconnection agreements, contingency plan, security configurations, configuration management plan, and incident response plan." | This is the sentence that puts the contingency plan inside the RMF package. The row asks whether the plan identifies the SSP it belongs to. |
| DoDI-E6-2a | Enclosure 6 ¶2.a Step 1 · 28 | "Categorize the system in accordance with Reference (e) and then document the results in the security plan. ... the IO identifies the potential impact (low, moderate, or high) resulting from loss of confidentiality, integrity, and availability". | Same evidence as N34-3.2.1a. |
| DoDI-E6-2b | Enclosure 6 ¶2.b(2) Step 2 · 29–30 | "Identify the security control baseline for the system, as provided in Reference (e), and document in the security plan." and "(b) Identifying overlays that apply to the IS or PIT system due to information contained within the system or environment of operation." and "If a selected control is not implemented, then the rationale for not implementing the controls must be documented in the security plan and POA&M." | The baseline and overlays come from CNSSI 1253 (Checklist E). The last sentence is the standard the report's NOT APPLICABLE rows must meet. |
| DoDI-E6-2d | Enclosure 6 ¶2.d(2)(a) Step 4 · 33 | "If no vulnerabilities are found through the process of executing the assessment procedures, the security control is recorded as compliant. If vulnerabilities are found, the control is recorded as NC in the POA&M, with sufficient explanation. Security controls that are not technically or procedurally relevant to the system, as determined by the AO, will be recorded as not applicable (NA) in the POA&M, with sufficient justification." | This is the DoD form of this skill's verdict rule; cite it when defending the absence of "not assessed". |
| DoDI-E6-2e | Enclosure 6 ¶2.e(2) Step 5 · 35 | "The ISSM assembles the security authorization package, consisting of the updated security plan, the SAR, and the POA&M. The security authorization package must also contain, or provide links to, the appropriate documentation for any security controls that are being satisfied through inheritance (e.g., security authorization packages, contract documents, MOAs, and SLAs)." | Whether the plan identifies what it inherits from Oracle (CP-6, CP-7, CP-8 provider agreements) and where the provider's authorization package is. `docs/07` §1a's design finding (OC1 regions carry no FedRAMP or DoD IL authorization) is the existing evidence and is itself a REFUTED for DoD use. |

Rows DoDI-3d and DoDI-E6-2b carry INACCESSIBLE sub-clauses (Knowledge Service, CNSSI 1253);
say which clause is inaccessible and which is assessed.

## 8. Checklist E: CNSSI 1253

CNSSI 1253 was not read. The listing at cnss.gov is readable (with TLS verification
disabled) and gives title, release date 08/01/2022 and file size; the document link
redirects to an error page; the overlay attachments are marked FOUO and require PKI, PIV or
CAC. DoDI 8510.01 Reference (e) cites it as "Committee on National Security Systems
Instruction 1253, 'Security Categorization and Control Selection for National Security
Systems,' March 27, 2014, as amended". That is the whole of what this skill can verify.

Every CNSSI 1253 row is INACCESSIBLE unless the organization running the audit supplies the
document, in which case the auditor quotes it and pins its hash. The rows exist so that the
count of INACCESSIBLE rows is visible:

| ID | What CNSSI 1253 is cited (by DoDI 8510.01) as providing | Row |
|---|---|---|
| CNSSI-cat | The categorization scheme for national security systems (DoDI ¶3.d, Encl. 6 ¶2.a). | INACCESSIBLE. Fallback: the plan's FIPS 199-style availability statement, if any (N34-3.2.1a). |
| CNSSI-base | The security control baselines (DoDI Encl. 6 ¶2.b(2)(a): "Selecting the applicable initial security control baseline from Reference (e) based on the IS categorization"). | INACCESSIBLE. Fallback: Checklist B assessed in full, baseline membership unknown. |
| CNSSI-ovl | Overlays (DoDI Encl. 6 ¶2.b(2)(b); the cnss.gov listing names attachments for Space Platform, Classified System, Cross Domain Solution, Intelligence and Privacy overlays). | INACCESSIBLE. Fallback: none; state that no overlay was applied and why. |
| CNSSI-param | DoD-specific assignment values (DoDI ¶3.d places these on the Knowledge Service, not in 1253 itself). | INACCESSIBLE. Fallback: FedRAMP High parameters (Checklist C) as the only public federal parameter set read, labeled as not DoD's. |

If the repo says anything about CNSSI 1253 beyond existence, title and date, that sentence
is a finding: `docs/07` currently hedges it as "(listing read; text login-gated)", which is
correct and must stay that way.

## 9. Where to look in this repository

This is a map, not evidence. The auditor still quotes the sentence.

| Requirement family | Files and sections |
|---|---|
| Objectives, background, scenario | `README.md` "The scenario", "Design in one paragraph", "Status"; `docs/01-architecture.md` §3 |
| Impact level, RTO/RPO/MTD, BIA | `docs/02-mtd-tiers.md` §1–§3; `checklists/tier-assignment-workshop.md` (output table, signatures); `docs/07` §1a first row; `README.md` "MTD tiers" |
| Assumptions and not-applicable situations | `docs/01-architecture.md` §1 (A1–A7); `docs/02` §5; `README.md` "Scope and limitations" |
| System description and diagrams | `docs/01-architecture.md` §2 (Mermaid), §4, §5; `docs/03-replication-matrix.md` §1, §4 |
| Roles, authority, succession | `checklists/dr-authority-matrix.md` (authority table, "Standing decisions", signature line); `checklists/contact-roster.md` §2; runbook headers ("Authority to invoke", "Approval") |
| Activation criteria and gate | `runbooks/RB-02-failover.md` §0; authority matrix standing decision 4 |
| Notification and contacts | `checklists/contact-roster.md` §1-§5; `checklists/pre-failover-precheck.md` §E; `runbooks/RB-01-switchover.md` §1 (T-24 h) |
| Outage assessment and forensics | `runbooks/RB-02-failover.md` §0 (Q1–Q4), §1 |
| Sequence and procedures | `runbooks/RB-01` §2–§3, `RB-02` §2–§5, `RB-03` §2–§3; `scripts/` as referenced |
| Escalation | `runbooks/RB-02-failover.md` §7b ("Escalate the MTD breach to the business immediately"), §7d; authority matrix rows for CFO delegate |
| Validation and reconstitution | `runbooks/RB-01-switchover.md` §5 (V1–V9), §6; `RB-02` §6, §8; `RB-03` §4–§5; `checklists/drill-timing-sheet.md` |
| Backups, alternate storage, retention | `docs/01-architecture.md` §4.1; `docs/03-replication-matrix.md` §1, §3; `runbooks/RB-05-replication-lifecycle.md` §5 step 5 and 7; `README.md` "Design in one paragraph" |
| Alternate site, separation, telecoms | `README.md` "The scenario"; `docs/01` §1 (A6), §3, §5.2–§5.3; `docs/07` §1a "Design finding for federal or DoD use" |
| Testing, exercises, after-action | `runbooks/RB-04-dr-drill.md` §1–§5; `checklists/drill-timing-sheet.md`; `docs/06-test-environments.md` §4; `evidence/README.md` |
| Training | nothing separate (KNOWN #4); `RB-04` §4 |
| Maintenance, review cadence, change record | nothing for the plan itself (KNOWN #1, G3, T12); `checklists/tier-assignment-workshop.md` closing note ("Re-run this workshop annually"); `docs/04-monitoring.md` §5 (drift, weekly) |
| Distribution and sensitivity | `evidence/README.md` "Sensitivity"; `README.md` "A note on evidence/"; precheck §E last item |
| Interconnections and partners | `docs/01` §4.4; `runbooks/RB-03-failback.md` §4 (partner endpoints); `RB-02` §6 (interface replay) |
| Inventory | `terraform/dr-resources.env.example`; `docs/03` §1; `docs/04` §5 |
| Cost, capacity | `docs/05-cost-and-teardown.md`; `docs/02` §4; `checklists/cost-model-template.md` |
| Cyber-event recovery, safe mode | `docs/01` §4.1 (retention lock); `RB-02` §7d; authority matrix standing decision 5 |

## 10. Output contract

Write `docs/compliance-audit.md`. Match `docs/citation-audit.md` in tone and structure:

1. **Header.** `**Date:**`, `**Scope:**` (the file list from §1 and the five instruments with
   edition and date), `**Method.**` (one paragraph: adversarial default, verdict definitions
   as in §1 of this skill, extraction method, the page arithmetic, the table-numbering note,
   and the tool limits actually encountered on the day, each with its HTTP status).
2. **Summary table.** Rows: Requirements enumerated (by checklist A–E and total); PASS;
   PARTIAL; REFUTED; NOT APPLICABLE; INACCESSIBLE; rows with no verdict (must be 0, and if
   it is not 0 the audit is unfinished and says so); NEW; KNOWN; CLOSED.
3. **Movement against known items.** One row per open issue and per G1–G4 / T12–T14: item ·
   status at last audit · status now · rows in this report that bear on it.
4. **Per-instrument results.** One section per checklist, one table per section, columns:
   `ID · Instrument · Section · Printed page · Verdict · Evidence (verbatim quote from the
   repository, with path and section heading; or the reason none exists; or the access
   failure) · Movement · Remediation`. Sub-verdicts for list requirements go in the Evidence
   cell as a numbered list, one line each.
5. **Remediation list.** Grouped REFUTED, then PARTIAL, then INACCESSIBLE; each item names
   the file to change and the sentence to add, the way issue #2 and #3 give a "Suggested
   shape". Where an existing issue already covers it, say "covered by #n" and add only what
   the issue lacks (for example CP-3's FedRAMP 10-day and 60-day figures for #4).
6. **URLs fetched.** Every URL with status and note, as `docs/citation-audit.md` §"URLs fetched".

Row count discipline: the number of rows in the per-instrument tables equals the number of
identifiers in Checklists A–E (A: 77, being 25 process rows, 14 plan-component rows and 38
template rows; B: 57 including 7 withdrawn; C: 35 selected + 14 not selected + the `FR-T-`
template rows you enumerate + 4 KSI; D: 9; E: 4). State the count you
audited against and reconcile any difference in the Method paragraph.

## 11. Before you finish

1. Every quote in the report greps against the extracted source text or the repository
   file. Run it; do not assume it.
2. No verdict column is empty, and no cell contains "not assessed", "TBD", "see above" or
   "as before".
3. Every INACCESSIBLE row has a URL, a status or wall type, a date, and a fallback.
4. Every NOT APPLICABLE row quotes the sentence that makes it so.
5. Every row touching #1–#4 or G1–G4 carries the identifier in Movement.
6. The summary counts add up to the number of rows.
7. Read the report once as the repository owner would. Cut anything that is not a fact, a
   quote, a verdict or a remediation.

If the audit is being re-run, do not edit the previous report's rows in place: rewrite the
file, keep the Date current, and put the previous date's summary counts in the Movement
section so the delta is visible without `git diff`.
