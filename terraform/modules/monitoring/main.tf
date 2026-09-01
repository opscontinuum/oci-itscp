####################################################################
# modules/monitoring — OCI Monitoring alarms -> OCI Notifications,
# using the exact namespaces/metrics documented in
# docs/04-monitoring.md §2: `oracle_oci_database` (ApplyLag,
# TransportLag — requires Database Management Diagnostics &
# Management enabled on the database), `oci_blockstore`
# (VolumeReplicationSecondsSinceLastSync), `oci_filestorage`
# (ReplicationRecoveryPointAge), plus an OCPU-floor alarm
# (`oci_database_cluster` / OcpusAllocated, docs/04 §2 table) and a
# notification topic.
#
# Verified against oracle/oci Terraform Registry docs (fetched
# 2026-09-01): oci_ons_notification_topic, oci_monitoring_alarm
# (namespace/query/severity/destinations/metric_compartment_id/
# is_enabled all Required; query is a plain MQL string).
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/monitoring_alarm
#
# Threshold values below are the CRITICAL column of docs/04 §2's alarm
# table; wire a second, WARNING-severity alarm per row if you also want
# the warning threshold to page separately.
####################################################################

terraform {
  required_providers {
    oci = {
      source                = "oracle/oci"
      configuration_aliases = [oci.ashburn]
    }
  }
}

resource "oci_ons_notification_topic" "dr" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  name           = var.notification_topic_name
  freeform_tags  = var.freeform_tags
}

# DG transport lag (PHX) — RPO signal. Critical > 30s (docs/04 §2).
resource "oci_monitoring_alarm" "dg_transport_lag_phx" {
  provider              = oci.ashburn
  count                 = var.apply_unlocked ? 1 : 0
  compartment_id        = var.compartment_id
  metric_compartment_id = var.compartment_id
  display_name          = "dg-transport-lag-phx-critical"
  namespace             = "oracle_oci_database"
  query                 = "TransportLag[1m]{primaryDbUniqueName = \"${var.db_primary_unique_name}\"}.mean() > 30"
  severity              = "CRITICAL"
  is_enabled            = true
  pending_duration      = "PT1M"
  destinations          = [oci_ons_notification_topic.dr[0].id]
  freeform_tags         = var.freeform_tags
}

# DG apply lag (PHX) — RTO signal. Critical > 15min (docs/04 §2).
resource "oci_monitoring_alarm" "dg_apply_lag_phx" {
  provider              = oci.ashburn
  count                 = var.apply_unlocked ? 1 : 0
  compartment_id        = var.compartment_id
  metric_compartment_id = var.compartment_id
  display_name          = "dg-apply-lag-phx-critical"
  namespace             = "oracle_oci_database"
  query                 = "ApplyLag[1m]{primaryDbUniqueName = \"${var.db_primary_unique_name}\"}.mean() > 900"
  severity              = "CRITICAL"
  is_enabled            = true
  pending_duration      = "PT1M"
  destinations          = [oci_ons_notification_topic.dr[0].id]
  freeform_tags         = var.freeform_tags
}

# DG apply lag (IAD2, SYNC leg) — any lag is a warning; critical > 60s
# (docs/04 §2 — RPO 0 depends on this leg staying synchronized).
resource "oci_monitoring_alarm" "dg_apply_lag_iad2" {
  provider              = oci.ashburn
  count                 = var.apply_unlocked ? 1 : 0
  compartment_id        = var.compartment_id
  metric_compartment_id = var.compartment_id
  display_name          = "dg-apply-lag-iad2-critical"
  namespace             = "oracle_oci_database"
  query                 = "ApplyLag[1m]{primaryDbUniqueName = \"${var.db_local_standby_unique_name}\"}.mean() > 60"
  severity              = "CRITICAL"
  is_enabled            = true
  pending_duration      = "PT1M"
  destinations          = [oci_ons_notification_topic.dr[0].id]
  freeform_tags         = var.freeform_tags
}

# Volume group replica age. Critical > 2hr (docs/04 §2).
resource "oci_monitoring_alarm" "volume_replica_age" {
  provider              = oci.ashburn
  count                 = var.apply_unlocked ? 1 : 0
  compartment_id        = var.compartment_id
  metric_compartment_id = var.compartment_id
  display_name          = "volume-replica-age-critical"
  namespace             = "oci_blockstore"
  query                 = "VolumeReplicationSecondsSinceLastSync[1m]{resourceId = \"${var.volume_replica_resource_id}\"}.mean() > 7200"
  severity              = "CRITICAL"
  is_enabled            = true
  pending_duration      = "PT1M"
  destinations          = [oci_ons_notification_topic.dr[0].id]
  freeform_tags         = var.freeform_tags
}

# FSS recovery point delta. Critical > 3x the replication interval — default
# interval is 60 min, so 180 min (docs/01 §4.4, docs/04 §2).
resource "oci_monitoring_alarm" "fss_recovery_point_age" {
  provider              = oci.ashburn
  count                 = var.apply_unlocked ? 1 : 0
  compartment_id        = var.compartment_id
  metric_compartment_id = var.compartment_id
  display_name          = "fss-recovery-point-age-critical"
  namespace             = "oci_filestorage"
  query                 = "ReplicationRecoveryPointAge[1m]{resourceId = \"${var.fss_replication_target_resource_id}\"}.mean() > 10800"
  severity              = "CRITICAL"
  is_enabled            = true
  pending_duration      = "PT1M"
  destinations          = [oci_ons_notification_topic.dr[0].id]
  freeform_tags         = var.freeform_tags
}

# PHX ExaDB-D OCPU below floor (docs/04 §2 — "OcpusAllocated"; scaling to 0
# silently converts Tier 1 into Tier 3, docs/05 §2).
resource "oci_monitoring_alarm" "phoenix_ocpu_floor" {
  provider              = oci.ashburn
  count                 = var.apply_unlocked ? 1 : 0
  compartment_id        = var.compartment_id
  metric_compartment_id = var.compartment_id
  display_name          = "phoenix-exadb-ocpu-below-floor"
  namespace             = "oci_database_cluster"
  query                 = "OcpusAllocated[1m]{resourceId = \"${var.phoenix_vm_cluster_resource_id}\"}.mean() < ${var.phoenix_vm_cluster_ocpu_floor}"
  severity              = "CRITICAL"
  is_enabled            = true
  pending_duration      = "PT5M"
  destinations          = [oci_ons_notification_topic.dr[0].id]
  freeform_tags         = var.freeform_tags
}
