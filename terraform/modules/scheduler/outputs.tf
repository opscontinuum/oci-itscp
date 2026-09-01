output "warm_posture_stop_schedule_id" {
  value = try(oci_resource_scheduler_schedule.warm_posture_stop[0].id, null)
}

output "targeted_instance_count" {
  value = length(var.stoppable_phoenix_instance_ids)
}
