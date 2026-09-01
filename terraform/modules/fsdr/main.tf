####################################################################
# modules/fsdr — OCI Full Stack Disaster Recovery: two DR Protection
# Groups as a peer pair, and the four DR plan types (docs/01 §6,
# docs/03 §4, RB-05 Phase 5).
#
# Verified against oracle/oci Terraform Registry docs (fetched
# 2026-09-01) plus the oracle/oci-go-sdk enum source (the Terraform
# provider markdown documents dr_plan.type and dr_protection_group.
# association.role as plain strings without printing their enum
# lists — confirmed instead against
# oracle/oci-go-sdk/disasterrecovery/{dr_plan_type,dr_protection_group_role,
# dr_protection_group_member_type}.go, generated code matching the
# published OCI API):
#   oci_disaster_recovery_dr_protection_group — association{role,peer_id,
#     peer_region}, log_location{bucket,namespace}, members{member_id,
#     member_type}. role: PRIMARY | STANDBY | UNCONFIGURED.
#     member_type: see variables.tf validation list — note DATABASE IS a
#     valid member_type per the SDK enum, even though the Terraform
#     registry markdown's own prose didn't spell it out explicitly.
#   oci_disaster_recovery_dr_plan — type: SWITCHOVER | FAILOVER |
#     START_DRILL | STOP_DRILL.
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/disaster_recovery_dr_protection_group
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/disaster_recovery_dr_plan
#
# This module creates one set of the four plan types, on the Ashburn
# (primary) DR Protection Group — the literal ask. A complete build also
# wants the mirrored set on the Phoenix DRPG for failback (RB-03), since a
# plan's steps are direction-specific; add a second `dr_plan` block set
# scoped to oci_disaster_recovery_dr_protection_group.phoenix once the
# Phoenix-side plan content is designed.
####################################################################

terraform {
  required_providers {
    oci = {
      source                = "oracle/oci"
      configuration_aliases = [oci.ashburn, oci.phoenix]
    }
  }
}

resource "oci_disaster_recovery_dr_protection_group" "ashburn" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "drpg-ebsprod-iad"
  freeform_tags  = var.freeform_tags

  association {
    role        = "PRIMARY"
    peer_id     = oci_disaster_recovery_dr_protection_group.phoenix[0].id
    peer_region = var.phoenix_peer_region
  }

  log_location {
    namespace = var.object_storage_namespace
    bucket    = var.ashburn_log_bucket
  }

  dynamic "members" {
    for_each = var.ashburn_members
    content {
      member_id   = members.value.member_id
      member_type = members.value.member_type
    }
  }
}

resource "oci_disaster_recovery_dr_protection_group" "phoenix" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "drpg-ebsprod-phx"
  freeform_tags  = var.freeform_tags

  association {
    role        = "STANDBY"
    peer_region = var.ashburn_peer_region
  }

  log_location {
    namespace = var.object_storage_namespace
    bucket    = var.phoenix_log_bucket
  }

  dynamic "members" {
    for_each = var.phoenix_members
    content {
      member_id   = members.value.member_id
      member_type = members.value.member_type
    }
  }
}

resource "oci_disaster_recovery_dr_plan" "switchover" {
  provider               = oci.ashburn
  count                  = var.apply_unlocked ? 1 : 0
  display_name           = "EBS Switchover IAD to PHX"
  dr_protection_group_id = oci_disaster_recovery_dr_protection_group.ashburn[0].id
  type                   = "SWITCHOVER"
  freeform_tags          = var.freeform_tags
}

resource "oci_disaster_recovery_dr_plan" "failover" {
  provider               = oci.ashburn
  count                  = var.apply_unlocked ? 1 : 0
  display_name           = "EBS Failover IAD to PHX"
  dr_protection_group_id = oci_disaster_recovery_dr_protection_group.ashburn[0].id
  type                   = "FAILOVER"
  freeform_tags          = var.freeform_tags
}

resource "oci_disaster_recovery_dr_plan" "start_drill" {
  provider               = oci.ashburn
  count                  = var.apply_unlocked ? 1 : 0
  display_name           = "EBS Start Drill"
  dr_protection_group_id = oci_disaster_recovery_dr_protection_group.ashburn[0].id
  type                   = "START_DRILL"
  freeform_tags          = var.freeform_tags
}

resource "oci_disaster_recovery_dr_plan" "stop_drill" {
  provider               = oci.ashburn
  count                  = var.apply_unlocked ? 1 : 0
  display_name           = "EBS Stop Drill"
  dr_protection_group_id = oci_disaster_recovery_dr_protection_group.ashburn[0].id
  type                   = "STOP_DRILL"
  freeform_tags          = var.freeform_tags
}
