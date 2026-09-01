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

variable "notification_topic_name" {
  type    = string
  default = "dr-alarms"
}

variable "db_primary_unique_name" {
  type    = string
  default = "EBSPROD_IAD"
}

variable "db_local_standby_unique_name" {
  type    = string
  default = "EBSPROD_IAD2"
}

variable "volume_replica_resource_id" {
  type    = string
  default = ""
}

variable "fss_replication_target_resource_id" {
  type    = string
  default = ""
}

variable "phoenix_vm_cluster_ocpu_floor" {
  description = "OCPU floor alarm threshold — alarms if allocated OCPU on the Phoenix VM cluster drops below this (docs/04 §2, docs/05 §2)."
  type        = number
  default     = 4
}

variable "phoenix_vm_cluster_resource_id" {
  type    = string
  default = ""
}
