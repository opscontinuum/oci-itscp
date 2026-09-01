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

# The Oracle Cloud Agent "Compute Instance Run Command" plugin name string is
# documented only in prose on the oci_core_instance registry page ("These are
# the management plugins: OS Management Service Agent and Compute Instance
# Run Command"), not as a literal `name =` example. Confirm the exact string
# with `oci compute-instance-agent instance-available-plugin list` against a
# real tenancy before ever applying this against one.
variable "run_command_plugin_name" {
  type    = string
  default = "Compute Instance Run Command"
}

variable "windows_image_id" {
  type        = string
  description = "OCID of the Windows Server custom image (MKS Toolkit + Oracle Cloud Agent baked in — docs/01-architecture.md A3). No default: this is estate-specific and must be supplied."
  default     = ""
}

# Node topology. Every node is a NON-MOVING Full Stack DR compute member
# (docs/03-replication-matrix.md §4) — it stays in its region; Full Stack DR
# attaches the replicated EBS data volume group to it at failover rather than
# moving the instance itself.
variable "ashburn_instances" {
  description = <<-EOT
    Ashburn windows app-tier instances, keyed by physical computer name
    (IAD-EBSWEB01, ...). Each gets its own boot volume (local, from
    windows_image_id) plus a data volume placed in a volume group that
    replicates cross-region to Phoenix (docs/01 §4.2).
  EOT
  type = map(object({
    availability_domain  = string
    subnet_id            = string
    role                 = string # web | cm | bi
    logical_hostname     = string # ebsweb01 etc — same value used on the PHX twin
    shape                = string
    ocpus                = number
    memory_in_gbs        = number
    boot_volume_size_gbs = number
    data_volume_size_gbs = number
    initial_state        = string # RUNNING | STOPPED
    nsg_ids              = list(string)
  }))
  default = {}
}

variable "phoenix_instances" {
  description = <<-EOT
    Phoenix twins — pre-provisioned, non-moving, stopped by default (except
    the always-on BI node reading the Active Data Guard standby). No data
    volume/volume group is created here: the replicated volume group replica
    from Ashburn is activated and attached to this instance by the Full
    Stack DR plan at switchover/failover time, not by steady-state Terraform.
  EOT
  type = map(object({
    availability_domain  = string
    subnet_id            = string
    role                 = string
    logical_hostname     = string
    shape                = string
    ocpus                = number
    memory_in_gbs        = number
    boot_volume_size_gbs = number
    initial_state        = string
    nsg_ids              = list(string)
  }))
  default = {}
}

variable "phoenix_replica_availability_domain" {
  type        = string
  description = "AD each Ashburn node's volume_group_replicas block targets in Phoenix."
  default     = "AD-1"
}
