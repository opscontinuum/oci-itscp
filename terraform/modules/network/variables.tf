variable "apply_unlocked" {
  type        = bool
  description = "Global apply-lock state from the root module. When false every resource in this module is count/for_each = 0."
}

variable "compartment_id" {
  type        = string
  description = "Compartment OCID that owns every network resource."
}

variable "freeform_tags" {
  type        = map(string)
  default     = {}
  description = "Freeform tags applied to every resource this module creates."
}

# --- Ashburn (primary) ------------------------------------------------------

variable "ashburn_vcn_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "ashburn_vcn_dns_label" {
  type    = string
  default = "iadvcn"
}

variable "ashburn_app_subnets" {
  description = "App-tier subnets in Ashburn, one per availability domain (docs/01-architecture.md §2: AD-1 and AD-2)."
  type = map(object({
    availability_domain = string
    cidr_block          = string
    dns_label           = string
  }))
  default = {
    ad1 = {
      availability_domain = "AD-1"
      cidr_block          = "10.10.1.0/24"
      dns_label           = "iadapp1"
    }
    ad2 = {
      availability_domain = "AD-2"
      cidr_block          = "10.10.2.0/24"
      dns_label           = "iadapp2"
    }
  }
}

variable "ashburn_db_subnet_cidr" {
  type    = string
  default = "10.10.10.0/24"
}

variable "ashburn_db_backup_subnet_cidr" {
  type    = string
  default = "10.10.11.0/24"
}

variable "ashburn_lb_subnet_cidr" {
  type    = string
  default = "10.10.20.0/24"
}

# --- Phoenix (DR) ------------------------------------------------------------

variable "phoenix_vcn_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "phoenix_vcn_dns_label" {
  type    = string
  default = "phxvcn"
}

variable "phoenix_app_subnets" {
  description = "App-tier subnets in Phoenix. us-phoenix-1 is modeled here with a single AD by default (DR_AD_COUNT); extend the map if your tenancy has more than one AD in this region — confirm the AD count for your tenancy before relying on this default."
  type = map(object({
    availability_domain = string
    cidr_block          = string
    dns_label           = string
  }))
  default = {
    ad1 = {
      availability_domain = "AD-1"
      cidr_block          = "10.20.1.0/24"
      dns_label           = "phxapp1"
    }
  }
}

variable "phoenix_db_subnet_cidr" {
  type    = string
  default = "10.20.10.0/24"
}

variable "phoenix_db_backup_subnet_cidr" {
  type    = string
  default = "10.20.11.0/24"
}

variable "phoenix_lb_subnet_cidr" {
  type    = string
  default = "10.20.20.0/24"
}

# --- Private DNS (docs/01-architecture.md §5.1 — logical host names) --------

variable "private_dns_zone_name" {
  type        = string
  default     = "ebs.internal"
  description = "Same zone name resolved region-locally through a per-region private view — the logical host name pattern (ebsweb01, ebscm01, ...) that keeps EBS context files unchanged across a role transition."
}
