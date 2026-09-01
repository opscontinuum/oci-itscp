####################################################################
# variables.tf — root inputs, including the apply lock.
#
# APPLY LOCK — Tier-C "author only, never apply" posture. Every
# resource across every module is gated on local.apply_unlocked. By
# default (unlock_apply = false), the entire configuration plans to
# zero resources: this repository is a worked example, and nothing in
# it has ever been applied against a real OCI tenancy. See
# terraform/README.md "Apply lock" for the full explanation and for
# what a real plan against your own tenancy requires (your own
# `oci session authenticate`, never credentials committed here).
####################################################################

variable "unlock_apply" {
  type        = bool
  default     = false
  description = "Set true, together with a matching spend_acknowledgement, to allow billable resources to plan/apply. Default false keeps this whole configuration at zero resources."
}

variable "spend_acknowledgement_duration" {
  description = "How long the operator accepts the estimated spend for, e.g. \"8h\", \"24h\", \"7d\". Required to unlock apply — see the smoke-8h Makefile target for the BOM this is sized against."
  type        = string
  default     = ""

  validation {
    condition     = var.spend_acknowledgement_duration == "" || can(regex("^[0-9]+(h|d)$", var.spend_acknowledgement_duration))
    error_message = "spend_acknowledgement_duration must look like \"8h\" or \"7d\" (an integer followed by h or d)."
  }
}

variable "spend_acknowledgement" {
  description = "Must equal exactly \"I accept the estimated cost for <spend_acknowledgement_duration>\" to unlock apply. This is a deliberate typed acknowledgement, not a rubber stamp — see the BOM output for what you are acknowledging."
  type        = string
  default     = ""
}

locals {
  required_spend_phrase = "I accept the estimated cost for ${var.spend_acknowledgement_duration}"

  apply_unlocked = (
    var.unlock_apply &&
    var.spend_acknowledgement_duration != "" &&
    var.spend_acknowledgement == local.required_spend_phrase
  )
}

# ---------------------------------------------------------------------------
# Regions, compartment, identity
# ---------------------------------------------------------------------------

variable "primary_region" {
  type    = string
  default = "us-ashburn-1"
}

variable "dr_region" {
  type    = string
  default = "us-phoenix-1"
}

variable "compartment_id" {
  description = "Compartment OCID for every resource. No real default — this is a public worked example with no live tenancy (README.md). Populate your own via a .tfvars file that stays untracked, mirroring terraform/dr-resources.env.example."
  type        = string
  default     = "ocid1.compartment.oc1..aaaaaaaaexampleplaceholderonly"
}

variable "object_storage_namespace" {
  type    = string
  default = "axexampleplaceholder"
}

variable "ssh_public_keys" {
  description = "SSH public keys for database VM clusters / DB systems. Windows compute does not use this (docs/01 A3 — MKS Toolkit / relinked Windows tier; initial admin credentials come from the Console/API, not an ssh key)."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Availability domains — placeholders. Real AD names are tenancy-specific
# (e.g. "kIdl:US-ASHBURN-1-AD-1") — look yours up with
# `oci iam availability-domain list` before ever applying.
# ---------------------------------------------------------------------------

variable "ashburn_ad1" {
  type    = string
  default = "AD-1"
}

variable "ashburn_ad2" {
  type    = string
  default = "AD-2"
}

variable "ashburn_ad3" {
  description = "FSFO Observer AD (docs/01 §3) — not built by this Terraform in this revision; reserved for a future compute module addition."
  type        = string
  default     = "AD-3"
}

variable "phoenix_ad1" {
  description = "us-phoenix-1 is modelled here with a single AD by default — confirm the AD count for your own tenancy/region before relying on this."
  type        = string
  default     = "AD-1"
}

# ---------------------------------------------------------------------------
# Database tier selector (docs/01 A2 / modules/database)
# ---------------------------------------------------------------------------

variable "database_tier" {
  type    = string
  default = "exadb-d"

  validation {
    condition     = contains(["exadb-d", "basedb"], var.database_tier)
    error_message = "database_tier must be \"exadb-d\" or \"basedb\"."
  }
}

# ---------------------------------------------------------------------------
# DR posture — informational selector feeding the scheduler/README/BOM.
# The actual posture lever in a real build is scripts/oci/set-dr-posture.sh
# (RB-05 §1); this variable exists so Terraform-side defaults (OCPU floor,
# stop schedule) can be read alongside it. See README §Status.
# ---------------------------------------------------------------------------

variable "dr_posture" {
  type    = string
  default = "warm"

  validation {
    condition     = contains(["warm", "hot"], var.dr_posture)
    error_message = "dr_posture must be \"warm\" or \"hot\" (RB-05-replication-lifecycle.md §1 — DRILL and FAILED_OVER are operational states this Terraform does not model)."
  }
}

variable "windows_image_id" {
  description = "OCID of the Windows Server custom image (docs/01 §4.2 — Oracle Cloud Agent, MKS Toolkit, JRE, Forms client baked in). Estate-specific, no meaningful default."
  type        = string
  default     = ""
}

variable "freeform_tags" {
  type    = map(string)
  default = {}
}

# ---------------------------------------------------------------------------
# Secrets — no usable defaults on purpose. Supply via TF_VAR_* or a secrets
# backend, never committed. Only used when database_tier = "basedb" /
# modules/recovery respectively; both stay "" (and therefore unused, since
# every consuming resource is also apply-lock-gated) otherwise.
# ---------------------------------------------------------------------------

variable "basedb_admin_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "protected_database_password" {
  type      = string
  default   = ""
  sensitive = true
}
