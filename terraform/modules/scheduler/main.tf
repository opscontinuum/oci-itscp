####################################################################
# modules/scheduler — OCI Resource Scheduler: the WARM-posture stop
# schedule for Phoenix Windows compute, excluding the always-on BI
# node (docs/05-cost-and-teardown.md §5, RB-05 §3).
#
# Verified against oracle/oci Terraform Registry docs (fetched
# 2026-09-01), cross-checked against oracle/oci-go-sdk
# resourcescheduler/schedule.go for the action/recurrence_type enum
# values (not printed in prose on the Terraform markdown page):
#   oci_resource_scheduler_schedule — action: START_RESOURCE |
#   STOP_RESOURCE | BACKUP_RESOURCE. recurrence_type: CRON | ICAL.
#   Must supply either `resources` or `resource_filters`; this module
#   uses `resources` (explicit instance OCIDs) since the stoppable set
#   already excludes the BI node by construction (modules/compute
#   outputs.stoppable_phoenix_instance_ids).
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/resource_scheduler_schedule
####################################################################

terraform {
  required_providers {
    oci = {
      source                = "oracle/oci"
      configuration_aliases = [oci.phoenix]
    }
  }
}

resource "oci_resource_scheduler_schedule" "warm_posture_stop" {
  provider           = oci.phoenix
  count              = var.apply_unlocked ? 1 : 0
  compartment_id     = var.compartment_id
  display_name       = "schedule-warm-posture-stop-phx"
  description        = "Holds the Phoenix Windows app tier stopped outside business hours / on weekends, excluding WIN-BI01 (always on). Belt-and-suspenders for the WARM posture — set-dr-posture.sh --posture warm is the primary mechanism."
  action             = "STOP_RESOURCE"
  recurrence_type    = "CRON"
  recurrence_details = var.stop_schedule_cron
  local_time_zone    = var.time_zone
  freeform_tags      = var.freeform_tags

  dynamic "resources" {
    for_each = var.stoppable_phoenix_instance_ids
    content {
      id = resources.value
    }
  }
}
