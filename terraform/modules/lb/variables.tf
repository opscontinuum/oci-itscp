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

variable "ashburn_lb_subnet_id" {
  type    = string
  default = ""
}

variable "phoenix_lb_subnet_id" {
  type    = string
  default = ""
}

variable "ashburn_lb_nsg_id" {
  type    = string
  default = ""
}

variable "phoenix_lb_nsg_id" {
  type    = string
  default = ""
}

variable "min_bandwidth_mbps" {
  type    = number
  default = 10
}

variable "max_bandwidth_mbps" {
  type    = number
  default = 100
}

variable "ashburn_backend_ip_addresses" {
  description = "Backend web-tier IPs behind the Ashburn LB (docs/01 §2 — spans AD-1 and AD-2)."
  type        = list(string)
  default     = []
}

variable "phoenix_backend_ip_addresses" {
  type    = list(string)
  default = []
}

variable "backend_port" {
  type    = number
  default = 443
}
