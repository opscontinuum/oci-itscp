output "steering_policy_id" {
  value = try(oci_dns_steering_policy.failover[0].id, null)
}

output "health_check_monitor_id" {
  value = try(oci_health_checks_http_monitor.ashburn[0].id, null)
}
