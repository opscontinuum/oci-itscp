output "ashburn_instance_ids" {
  value = { for k, i in oci_core_instance.ashburn : k => i.id }
}

output "phoenix_instance_ids" {
  value = { for k, i in oci_core_instance.phoenix : k => i.id }
}

output "ashburn_volume_group_ids" {
  value = { for k, vg in oci_core_volume_group.ashburn : k => vg.id }
}

output "always_on_phoenix_instance_ids" {
  description = "Phoenix instances whose var.initial_state is RUNNING — excluded from the WARM-posture stop schedule (the BI tier, which reads the Active Data Guard standby continuously)."
  value       = [for k, i in local.phoenix_instances : oci_core_instance.phoenix[k].id if i.initial_state == "RUNNING"]
}

output "stoppable_phoenix_instance_ids" {
  description = "Phoenix instances eligible for the WARM-posture stop schedule."
  value       = [for k, i in local.phoenix_instances : oci_core_instance.phoenix[k].id if i.initial_state != "RUNNING"]
}

output "ashburn_instance_states" {
  value = { for k, i in oci_core_instance.ashburn : k => i.state }
}

output "phoenix_instance_states" {
  value = { for k, i in oci_core_instance.phoenix : k => i.state }
}

output "ashburn_run_command_plugin_states" {
  description = "desired_state of the Run Command plugin per Ashburn instance — must be ENABLED everywhere (docs/01 §6: FSDR user-defined steps fail at that step otherwise)."
  value       = { for k, i in oci_core_instance.ashburn : k => i.agent_config[0].plugins_config[0].desired_state }
}

output "phoenix_run_command_plugin_states" {
  value = { for k, i in oci_core_instance.phoenix : k => i.agent_config[0].plugins_config[0].desired_state }
}
