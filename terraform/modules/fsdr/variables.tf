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
  type    = string
  default = ""
}

variable "ashburn_log_bucket" {
  type    = string
  default = ""
}

variable "phoenix_log_bucket" {
  type    = string
  default = ""
}

variable "ashburn_members" {
  description = "DR Protection Group members on the Ashburn (primary) side — compute, volume group, database, file system, object storage bucket, load balancer (docs/03 §4)."
  type = list(object({
    member_id   = string
    member_type = string
  }))
  default = []

  validation {
    condition = alltrue([
      for m in var.ashburn_members : contains([
        "COMPUTE_INSTANCE", "COMPUTE_INSTANCE_MOVABLE", "COMPUTE_INSTANCE_NON_MOVABLE",
        "VOLUME_GROUP", "DATABASE", "AUTONOMOUS_DATABASE", "AUTONOMOUS_CONTAINER_DATABASE",
        "LOAD_BALANCER", "NETWORK_LOAD_BALANCER", "FILE_SYSTEM", "OKE_CLUSTER",
        "OBJECT_STORAGE_BUCKET", "MYSQL_DB_SYSTEM", "INTEGRATION_INSTANCE",
      ], m.member_type)
    ])
    error_message = "member_type must be one of the DrProtectionGroupMemberTypeEnum values (oracle/oci-go-sdk disasterrecovery/dr_protection_group_member_type.go)."
  }
}

variable "phoenix_members" {
  description = "DR Protection Group members on the Phoenix (standby) side — the non-moving compute twins, plus any member types the standby-side plan groups need."
  type = list(object({
    member_id   = string
    member_type = string
  }))
  default = []
}

variable "phoenix_peer_region" {
  type    = string
  default = "us-phoenix-1"
}

variable "ashburn_peer_region" {
  type    = string
  default = "us-ashburn-1"
}
