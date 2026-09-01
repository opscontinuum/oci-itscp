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

variable "public_zone_id" {
  description = "OCID of the PUBLIC DNS zone the steering policy attaches to (docs/01 §5.2 — Traffic Management is only available for public DNS). Not created by this module: bring your own public zone/domain."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Public FQDN steered by the FAILOVER policy, e.g. ebs.example.com."
  type        = string
  default     = "ebs.example.com"
}

variable "ashburn_lb_ip" {
  type    = string
  default = "203.0.113.10"
}

variable "phoenix_lb_ip" {
  type    = string
  default = "203.0.113.20"
}

variable "ttl_seconds" {
  type    = number
  default = 30
}

variable "ashburn_health_check_targets" {
  type    = list(string)
  default = []
}

variable "phoenix_health_check_targets" {
  type    = list(string)
  default = []
}
