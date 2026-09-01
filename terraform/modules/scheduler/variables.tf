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

variable "stoppable_phoenix_instance_ids" {
  description = "Phoenix Windows instance OCIDs to hold in the WARM posture (stopped) — every node EXCEPT the always-on BI tier, which reads the Active Data Guard standby continuously (docs/01 §4.5, docs/05 §3)."
  type        = list(string)
  default     = []
}

variable "stop_schedule_cron" {
  description = "UNIX cron for the WARM-posture stop schedule — 'hold WARM outside business hours and on weekends' (docs/05-cost-and-teardown.md §5). Default: 8pm daily."
  type        = string
  default     = "0 20 * * *"
}

variable "time_zone" {
  type    = string
  default = "US/Eastern"
}
