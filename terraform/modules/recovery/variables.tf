variable "apply_unlocked" {
  type        = bool
  description = "Global apply-lock state from the root module."
}

variable "compartment_id" {
  type = string
}

variable "freeform_tags" {
  type    = map(string)
  default = {}
}

variable "ashburn_vcn_id" {
  type    = string
  default = ""
}

variable "ashburn_recovery_subnet_ids" {
  type    = list(string)
  default = []
}

variable "primary_database_id" {
  description = "OCID of whichever database is currently primary — Ashburn at build time (docs/01 §4.1: Recovery Service protects the primary, in whichever region is primary)."
  type        = string
  default     = ""
}

variable "backup_retention_period_days" {
  type    = number
  default = 60

  validation {
    condition     = var.backup_retention_period_days > 0 && var.backup_retention_period_days <= 95
    error_message = "Recovery Service retains at most 95 days (docs/03-replication-matrix.md R2)."
  }
}

variable "retention_lock_enabled" {
  description = <<-EOT
    Disabled (false) by default. Retention lock adds a minimum 14-day delay
    before permanently locking the retention period, and once locked the
    period cannot be decreased (docs/05-cost-and-teardown.md §4). This
    repository is a worked example with no real backups to protect; leave it
    off here and turn it on deliberately, with a documented change ticket,
    once real data exists — a retention lock is difficult to reverse.
  EOT
  type        = bool
  default     = false
}

variable "retention_lock_time" {
  description = "RFC3339 datetime for policy_locked_date_time. Only used when retention_lock_enabled = true. Must be at least 14 days out; not validated here since 'now' isn't available at plan time — validate the value you supply before applying."
  type        = string
  default     = null
}

variable "protected_database_display_name" {
  type    = string
  default = "ebsprod-protected-database"
}

variable "protected_database_password" {
  description = "Password credential used by Recovery Service to connect to the protected database. No usable default — supply via TF_VAR or a secrets backend."
  type        = string
  default     = ""
  sensitive   = true
}

variable "db_unique_name" {
  type    = string
  default = "EBSPROD_IAD"
}
