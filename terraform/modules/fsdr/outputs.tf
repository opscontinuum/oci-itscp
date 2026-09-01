output "ashburn_drpg_id" {
  value = try(oci_disaster_recovery_dr_protection_group.ashburn[0].id, null)
}

output "phoenix_drpg_id" {
  value = try(oci_disaster_recovery_dr_protection_group.phoenix[0].id, null)
}

output "plan_ids" {
  value = {
    switchover  = try(oci_disaster_recovery_dr_plan.switchover[0].id, null)
    failover    = try(oci_disaster_recovery_dr_plan.failover[0].id, null)
    start_drill = try(oci_disaster_recovery_dr_plan.start_drill[0].id, null)
    stop_drill  = try(oci_disaster_recovery_dr_plan.stop_drill[0].id, null)
  }
}
