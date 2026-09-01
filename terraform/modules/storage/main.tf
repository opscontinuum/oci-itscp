####################################################################
# modules/storage — File Storage (interface landing dirs + cross-
# region replication), Object Storage (interchange buckets + cross-
# region replication policy), and the per-DR-Protection-Group FSDR
# log buckets (Standard tier, no replication).
#
# Verified against oracle/oci Terraform Registry docs (fetched
# 2026-09-01): oci_file_storage_file_system, oci_file_storage_export_set,
# oci_file_storage_export, oci_file_storage_mount_target,
# oci_file_storage_replication (source_id/target_id/replication_interval —
# there is NO oci_file_storage_replication_target resource; the
# ReplicationTarget is auto-created and only exposed as this
# resource's computed replication_target_id), oci_objectstorage_bucket,
# oci_objectstorage_replication_policy (bucket/namespace/name/
# destination_bucket_name/destination_region_name — all required, no
# optional args documented).
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/file_storage_replication
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/objectstorage_replication_policy
####################################################################

terraform {
  required_providers {
    oci = {
      source                = "oracle/oci"
      configuration_aliases = [oci.ashburn, oci.phoenix]
    }
  }
}

locals {
  buckets = var.apply_unlocked ? var.object_storage_buckets : []
}

# ---------------------------------------------------------------------------
# File Storage — interface landing directories, custom file drops
# (docs/01 §4.4). Replication target is read-only until exported (one-way
# door per event — docs/03 §2); never torn down in WARM posture.
# ---------------------------------------------------------------------------

resource "oci_file_storage_file_system" "ashburn" {
  provider            = oci.ashburn
  count               = var.apply_unlocked ? 1 : 0
  compartment_id      = var.compartment_id
  availability_domain = var.ashburn_fss_availability_domain
  display_name        = "fs-ebs-interfaces-iad"
  freeform_tags       = var.freeform_tags
}

resource "oci_file_storage_file_system" "phoenix" {
  provider            = oci.phoenix
  count               = var.apply_unlocked ? 1 : 0
  compartment_id      = var.compartment_id
  availability_domain = var.phoenix_fss_availability_domain
  display_name        = "fs-ebs-interfaces-phx"
  freeform_tags       = var.freeform_tags
}

resource "oci_file_storage_mount_target" "ashburn" {
  provider            = oci.ashburn
  count               = var.apply_unlocked ? 1 : 0
  compartment_id      = var.compartment_id
  availability_domain = var.ashburn_fss_availability_domain
  subnet_id           = var.ashburn_fss_subnet_id
  display_name        = "mt-ebs-interfaces-iad"
  freeform_tags       = var.freeform_tags
}

resource "oci_file_storage_mount_target" "phoenix" {
  provider            = oci.phoenix
  count               = var.apply_unlocked ? 1 : 0
  compartment_id      = var.compartment_id
  availability_domain = var.phoenix_fss_availability_domain
  subnet_id           = var.phoenix_fss_subnet_id
  display_name        = "mt-ebs-interfaces-phx"
  freeform_tags       = var.freeform_tags
}

resource "oci_file_storage_export" "ashburn" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  export_set_id  = oci_file_storage_mount_target.ashburn[0].export_set_id
  file_system_id = oci_file_storage_file_system.ashburn[0].id
  path           = "/ebs-interfaces"

  export_options {
    source = "0.0.0.0/0"
    access = "READ_WRITE"
  }
}

# Cross-region File System Replication — snapshot-delta based, minimum 15
# minute interval, target read-only until exported (docs/01 §4.4, docs/03 R5).
resource "oci_file_storage_replication" "ashburn_to_phoenix" {
  provider             = oci.ashburn
  count                = var.apply_unlocked ? 1 : 0
  compartment_id       = var.compartment_id
  display_name         = "repl-ebs-interfaces-iad-to-phx"
  source_id            = oci_file_storage_file_system.ashburn[0].id
  target_id            = oci_file_storage_file_system.phoenix[0].id
  replication_interval = var.fss_replication_interval_minutes
}

# ---------------------------------------------------------------------------
# Object Storage — interface/batch/archive interchange (docs/01 §4.4 option
# C, the recommended primary path for all batch interchange)
# ---------------------------------------------------------------------------

resource "oci_objectstorage_bucket" "ashburn" {
  provider       = oci.ashburn
  for_each       = toset(local.buckets)
  compartment_id = var.compartment_id
  namespace      = var.object_storage_namespace
  name           = "${each.key}-iad"
  storage_tier   = var.object_storage_tier
  freeform_tags  = var.freeform_tags
}

resource "oci_objectstorage_bucket" "phoenix" {
  provider       = oci.phoenix
  for_each       = toset(local.buckets)
  compartment_id = var.compartment_id
  namespace      = var.object_storage_namespace
  name           = "${each.key}-phx"
  storage_tier   = var.object_storage_tier
  freeform_tags  = var.freeform_tags
}

resource "oci_objectstorage_replication_policy" "ashburn_to_phoenix" {
  provider                = oci.ashburn
  for_each                = toset(local.buckets)
  bucket                  = oci_objectstorage_bucket.ashburn[each.key].name
  namespace               = var.object_storage_namespace
  name                    = "repl-${each.key}-iad-to-phx"
  destination_bucket_name = oci_objectstorage_bucket.phoenix[each.key].name
  destination_region_name = "us-phoenix-1"
}

# ---------------------------------------------------------------------------
# FSDR plan-execution log buckets — one per DR Protection Group, Standard
# tier, NO replication (RB-05 Phase 5, docs/01 §6). These are consumed by the
# fsdr module's log_location block.
# ---------------------------------------------------------------------------

resource "oci_objectstorage_bucket" "fsdr_logs_ashburn" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  namespace      = var.object_storage_namespace
  name           = var.fsdr_log_bucket_names.ashburn
  storage_tier   = "Standard"
  freeform_tags  = var.freeform_tags
}

resource "oci_objectstorage_bucket" "fsdr_logs_phoenix" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  namespace      = var.object_storage_namespace
  name           = var.fsdr_log_bucket_names.phoenix
  storage_tier   = "Standard"
  freeform_tags  = var.freeform_tags
}
