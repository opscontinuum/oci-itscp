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

variable "database_tier" {
  description = <<-EOT
    "exadb-d"  — Exadata Database Service on Dedicated Infrastructure
                 (docs/01-architecture.md A2, the plan's actual design).
    "basedb"   — Base Database Service, the Tier-C cheap alternative used
                 only for the OCI Cost Estimator BOM (README §Status /
                 docs/05-cost-and-teardown.md). Loses HCC eligibility
                 (docs/01 A5), ExaDB-D elastic OCPU scaling (docs/05 §2)
                 and Full Stack DR's ExaDB-D-specific snapshot-standby
                 drill precheck coverage (docs/01 §6).
  EOT
  type        = string
  default     = "exadb-d"

  validation {
    condition     = contains(["exadb-d", "basedb"], var.database_tier)
    error_message = "database_tier must be \"exadb-d\" or \"basedb\"."
  }
}

variable "ashburn_ad" {
  type    = string
  default = "AD-1"
}

variable "phoenix_ad" {
  type    = string
  default = "AD-1"
}

variable "ashburn_db_subnet_id" {
  type    = string
  default = ""
}

variable "ashburn_db_backup_subnet_id" {
  type    = string
  default = ""
}

variable "phoenix_db_subnet_id" {
  type    = string
  default = ""
}

variable "phoenix_db_backup_subnet_id" {
  type    = string
  default = ""
}

variable "ssh_public_keys" {
  type      = list(string)
  default   = []
  sensitive = false
}

# --- exadb-d tier -------------------------------------------------------

variable "exadata_shape" {
  type    = string
  default = "Exadata.X9M"
}

variable "exadata_compute_count" {
  type    = number
  default = 2
}

variable "exadata_storage_count" {
  type    = number
  default = 3
}

variable "exadb_node_count" {
  description = "Nodes per VM cluster, used only to size the cpu_core_count floor validation below (node_count itself is a computed/exported attribute on oci_database_cloud_vm_cluster, not a settable argument)."
  type        = number
  default     = 2
}

variable "ashburn_cpu_core_count" {
  description = "cpu_core_count on the Ashburn (primary) cloud VM cluster. Must be >= 2 per node (docs/05-cost-and-teardown.md §2 — the VM cluster's per-VM OCPU floor)."
  type        = number
  default     = 32

  validation {
    condition     = var.ashburn_cpu_core_count >= 2 * var.exadb_node_count
    error_message = "ashburn_cpu_core_count must be at least 2 OCPU per node (Oracle's documented VM cluster floor)."
  }
}

variable "phoenix_cpu_core_count" {
  description = "cpu_core_count on the Phoenix (standby) cloud VM cluster — the OCPU floor posture (docs/05 §2, dr-resources.env.example DR_OCPU_FLOOR). Must be >= 2 per node; 0 shuts the VM cluster down entirely and silently converts Tier 1 into Tier 3."
  type        = number
  default     = 4

  validation {
    condition     = var.phoenix_cpu_core_count >= 2 * var.exadb_node_count
    error_message = "phoenix_cpu_core_count must be at least 2 OCPU per node — scaling to 0 shuts the whole VM cluster down and stops redo apply (docs/05 §2)."
  }
}

variable "gi_version" {
  type    = string
  default = "19.0.0.0"
}

# --- basedb tier ----------------------------------------------------------

variable "basedb_shape" {
  type    = string
  default = "VM.Standard2.2"
}

variable "basedb_db_version" {
  type    = string
  default = "19.0.0.0"
}

variable "basedb_db_name" {
  type    = string
  default = "EBSPROD"
}

variable "basedb_data_storage_size_gb" {
  type    = number
  default = 256
}

variable "basedb_admin_password" {
  description = "SYS/SYSTEM/PDB admin + TDE wallet password. No usable default on purpose — must be supplied via TF_VAR or a secrets backend, never committed."
  type        = string
  default     = ""
  sensitive   = true
}

variable "basedb_license_model" {
  description = "BYOL by default (docs/05-cost-and-teardown.md §4 — check entitlement before committing to a value)."
  type        = string
  default     = "BRING_YOUR_OWN_LICENSE"

  validation {
    condition     = contains(["LICENSE_INCLUDED", "BRING_YOUR_OWN_LICENSE"], var.basedb_license_model)
    error_message = "basedb_license_model must be LICENSE_INCLUDED or BRING_YOUR_OWN_LICENSE."
  }
}

variable "basedb_data_guard_protection_mode" {
  type    = string
  default = "MAXIMUM_PERFORMANCE"
}

variable "basedb_data_guard_transport_type" {
  type    = string
  default = "ASYNC"
}
