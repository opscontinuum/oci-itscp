output "protection_policy_id" {
  value = try(oci_recovery_protection_policy.standard[0].id, null)
}

output "protected_database_id" {
  value = try(oci_recovery_protected_database.ashburn[0].id, null)
}

output "recovery_service_subnet_id" {
  value = try(oci_recovery_recovery_service_subnet.ashburn[0].id, null)
}

output "retention_lock_enabled" {
  value = var.retention_lock_enabled
}
