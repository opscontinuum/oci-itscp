####################################################################
# modules/recovery — Oracle Database Autonomous Recovery Service,
# primary only (docs/01 §4.1: "Recovery Service protects the
# primary, in whichever region is primary" — at build time that is
# Ashburn; a role change requires re-enabling protection on the new
# primary per RB-05 Phase-2/5-decommission notes, which is an
# operational runbook step, not something this steady-state module
# re-points automatically).
#
# Verified against oracle/oci Terraform Registry docs (fetched
# 2026-09-01): oci_recovery_recovery_service_subnet, oci_recovery_
# protection_policy (retention lock IS a plain attribute on this
# resource — policy_locked_date_time — not a separate resource or
# action), oci_recovery_protected_database (recovery_service_subnets
# is a repeatable block of { recovery_service_subnet_id }, not a
# flat list of OCIDs).
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/recovery_protection_policy
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/recovery_protected_database
####################################################################

terraform {
  required_providers {
    oci = {
      source                = "oracle/oci"
      configuration_aliases = [oci.ashburn]
    }
  }
}

resource "oci_recovery_recovery_service_subnet" "ashburn" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "recovery-subnet-ebsprod-iad"
  vcn_id         = var.ashburn_vcn_id
  subnets        = var.ashburn_recovery_subnet_ids
}

resource "oci_recovery_protection_policy" "standard" {
  provider                        = oci.ashburn
  count                           = var.apply_unlocked ? 1 : 0
  compartment_id                  = var.compartment_id
  display_name                    = "protection-policy-ebsprod"
  backup_retention_period_in_days = var.backup_retention_period_days
  # Retention lock disabled by default — see variables.tf for why.
  policy_locked_date_time = var.retention_lock_enabled ? var.retention_lock_time : null
  freeform_tags           = var.freeform_tags
}

resource "oci_recovery_protected_database" "ashburn" {
  provider             = oci.ashburn
  count                = var.apply_unlocked ? 1 : 0
  compartment_id       = var.compartment_id
  display_name         = var.protected_database_display_name
  db_unique_name       = var.db_unique_name
  password             = var.protected_database_password
  protection_policy_id = oci_recovery_protection_policy.standard[0].id
  database_id          = var.primary_database_id
  freeform_tags        = var.freeform_tags

  recovery_service_subnets {
    recovery_service_subnet_id = oci_recovery_recovery_service_subnet.ashburn[0].id
  }

  lifecycle {
    ignore_changes = [password]
  }
}
