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

variable "object_storage_namespace" {
  type        = string
  description = "Tenancy's Object Storage namespace. Estate-specific — no meaningful default."
  default     = ""
}

# --- File Storage (interface landing directories, docs/01 §4.4 option A) ---

variable "ashburn_fss_availability_domain" {
  type    = string
  default = "AD-1"
}

variable "phoenix_fss_availability_domain" {
  type    = string
  default = "AD-1"
}

variable "ashburn_fss_subnet_id" {
  type    = string
  default = ""
}

variable "phoenix_fss_subnet_id" {
  type    = string
  default = ""
}

variable "fss_replication_interval_minutes" {
  description = "Minutes between FSS replication snapshots. Minimum 15, default 60 if unset by Oracle (docs/01 §4.4, docs/03 R5)."
  type        = number
  default     = 60

  validation {
    condition     = var.fss_replication_interval_minutes >= 15
    error_message = "OCI File Storage Replication's minimum interval is 15 minutes."
  }
}

# --- Object Storage (interface/batch interchange, docs/01 §4.4 option C) ---

variable "object_storage_buckets" {
  description = "Interchange buckets replicated Ashburn -> Phoenix, keyed by name."
  type        = set(string)
  default     = ["ebs-interfaces", "ebs-archive"]
}

variable "object_storage_tier" {
  type    = string
  default = "Standard"

  validation {
    condition     = contains(["Standard", "Archive"], var.object_storage_tier)
    error_message = "oci_objectstorage_bucket storage_tier accepts only Standard or Archive."
  }
}

# --- FSDR plan-execution log buckets (one per DR Protection Group) ---

variable "fsdr_log_bucket_names" {
  description = "One Standard-tier, no-replication bucket per DR Protection Group, reserved for that group's plan execution logs (docs/01 §6, RB-05 Phase 5)."
  type = object({
    ashburn = string
    phoenix = string
  })
  default = {
    ashburn = "ebs-fsdr-logs-iad"
    phoenix = "ebs-fsdr-logs-phx"
  }
}
