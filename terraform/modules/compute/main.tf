####################################################################
# modules/compute — Windows non-moving instances, EBS data volume
# groups with cross-region replication, Oracle Cloud Agent Run
# Command plugin.
#
# Verified against oracle/oci Terraform Registry docs (fetched
# 2026-09-01): oci_core_instance (state="STOPPED" is a direct,
# Updatable top-level argument — no separate instance_action
# resource needed), oci_core_volume, oci_core_volume_group
# (volume_group_replicas block — cross-region replication lives on
# this SAME resource, there is no separate replica resource),
# oci_core_volume_attachment.
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_instance
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_volume_group
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
  ashburn_instances = var.apply_unlocked ? var.ashburn_instances : {}
  phoenix_instances = var.apply_unlocked ? var.phoenix_instances : {}
}

# ---------------------------------------------------------------------------
# Ashburn instances (production + local HA twins)
# ---------------------------------------------------------------------------

resource "oci_core_instance" "ashburn" {
  provider            = oci.ashburn
  for_each            = local.ashburn_instances
  compartment_id      = var.compartment_id
  availability_domain = each.value.availability_domain
  shape               = each.value.shape
  display_name        = each.key
  state               = each.value.initial_state
  freeform_tags       = var.freeform_tags

  shape_config {
    ocpus         = each.value.ocpus
    memory_in_gbs = each.value.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = var.windows_image_id
    boot_volume_size_in_gbs = each.value.boot_volume_size_gbs
  }

  create_vnic_details {
    subnet_id        = each.value.subnet_id
    nsg_ids          = each.value.nsg_ids
    hostname_label   = each.value.logical_hostname
    assign_public_ip = false
  }

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false

    plugins_config {
      name          = var.run_command_plugin_name
      desired_state = "ENABLED"
    }
  }

}

# ---------------------------------------------------------------------------
# Phoenix instances (pre-provisioned, non-moving, pilot light)
# ---------------------------------------------------------------------------

resource "oci_core_instance" "phoenix" {
  provider            = oci.phoenix
  for_each            = local.phoenix_instances
  compartment_id      = var.compartment_id
  availability_domain = each.value.availability_domain
  shape               = each.value.shape
  display_name        = each.key
  state               = each.value.initial_state
  freeform_tags       = var.freeform_tags

  shape_config {
    ocpus         = each.value.ocpus
    memory_in_gbs = each.value.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = var.windows_image_id
    boot_volume_size_in_gbs = each.value.boot_volume_size_gbs
  }

  create_vnic_details {
    subnet_id        = each.value.subnet_id
    nsg_ids          = each.value.nsg_ids
    hostname_label   = each.value.logical_hostname
    assign_public_ip = false
  }

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false

    plugins_config {
      name          = var.run_command_plugin_name
      desired_state = "ENABLED"
    }
  }

}

# ---------------------------------------------------------------------------
# EBS data volumes (fs1/fs2/fs_ne + $APPLCSF, represented as one data volume
# per Ashburn node — docs/01 §4.2, §4.3) grouped for cross-region replication
# ---------------------------------------------------------------------------

resource "oci_core_volume" "ashburn_data" {
  provider            = oci.ashburn
  for_each            = local.ashburn_instances
  compartment_id      = var.compartment_id
  availability_domain = each.value.availability_domain
  display_name        = "${each.key}-data"
  size_in_gbs         = each.value.data_volume_size_gbs
  freeform_tags       = var.freeform_tags
}

# One volume group per Ashburn node — individually replicated volumes are not
# mutually consistent (docs/01 §4.2), so fs1/fs2/fs_ne always move together.
resource "oci_core_volume_group" "ashburn" {
  provider            = oci.ashburn
  for_each            = local.ashburn_instances
  compartment_id      = var.compartment_id
  availability_domain = each.value.availability_domain
  display_name        = "${each.key}-volume-group"
  freeform_tags       = var.freeform_tags

  source_details {
    type       = "volumeIds"
    volume_ids = [oci_core_volume.ashburn_data[each.key].id]
  }

  # Cross-region Volume Group Replication (docs/03-replication-matrix.md R3).
  # This is a full one-way door per event (docs/03 §2) — never torn down in
  # WARM posture, only the destination compute is stopped.
  volume_group_replicas {
    availability_domain = var.phoenix_replica_availability_domain
    display_name        = "${each.key}-volume-group-replica-phx"
  }
}

resource "oci_core_volume_attachment" "ashburn_data" {
  provider        = oci.ashburn
  for_each        = local.ashburn_instances
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.ashburn[each.key].id
  volume_id       = oci_core_volume.ashburn_data[each.key].id
}
