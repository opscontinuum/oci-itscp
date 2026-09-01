-- check-hcc.sql
-- Purpose: determine whether any segment uses Hybrid Columnar Compression.
--
-- WHY THIS MATTERS: HCC segments can only be queried on Exadata storage (and ZFS
-- Storage Appliance / Pillar Axiom). If any row returns here, the Phoenix standby
-- MUST be Exadata -- there is no cost-reduction path to Base Database Service.
-- See docs/01-architecture.md assumption A5 and docs/05-cost-and-teardown.md §2.
--
-- Run as a user with access to DBA views, on the PRIMARY.

SET PAGESIZE 200 LINESIZE 200
COLUMN owner        FORMAT A30
COLUMN segment_name FORMAT A40
COLUMN compress_for FORMAT A20

PROMPT === Tables using HCC ===
SELECT owner, table_name AS segment_name, compress_for
  FROM dba_tables
 WHERE compression = 'ENABLED'
   AND (compress_for LIKE 'QUERY%' OR compress_for LIKE 'ARCHIVE%')
 ORDER BY owner, table_name;

PROMPT === Partitions using HCC ===
SELECT table_owner AS owner, table_name || '.' || partition_name AS segment_name, compress_for
  FROM dba_tab_partitions
 WHERE compression = 'ENABLED'
   AND (compress_for LIKE 'QUERY%' OR compress_for LIKE 'ARCHIVE%')
 ORDER BY table_owner, table_name, partition_name;

PROMPT === Subpartitions using HCC ===
SELECT table_owner AS owner,
       table_name || '.' || partition_name || '.' || subpartition_name AS segment_name,
       compress_for
  FROM dba_tab_subpartitions
 WHERE compression = 'ENABLED'
   AND (compress_for LIKE 'QUERY%' OR compress_for LIKE 'ARCHIVE%')
 ORDER BY table_owner, table_name, partition_name, subpartition_name;

PROMPT
PROMPT === VERDICT ===
PROMPT Zero rows above  -> a non-Exadata standby is technically possible (weigh other trade-offs).
PROMPT Any rows above   -> the Phoenix standby MUST be Exadata. Treat as a hard constraint.
