output "ashburn_exadata_infrastructure_id" {
  value = try(oci_database_cloud_exadata_infrastructure.ashburn[0].id, null)
}

output "phoenix_exadata_infrastructure_id" {
  value = try(oci_database_cloud_exadata_infrastructure.phoenix[0].id, null)
}

output "ashburn_vm_cluster_id" {
  value = try(oci_database_cloud_vm_cluster.ashburn[0].id, null)
}

output "phoenix_vm_cluster_id" {
  value = try(oci_database_cloud_vm_cluster.phoenix[0].id, null)
}

output "ashburn_db_system_id" {
  value = try(oci_database_db_system.ashburn[0].id, null)
}

output "ashburn_primary_database_id" {
  description = "Resolved primary database OCID for the basedb tier — feeds modules/recovery and modules/fsdr."
  value       = try(data.oci_database_databases.ashburn[0].databases[0].id, null)
}

output "phoenix_data_guard_association_id" {
  value = try(oci_database_data_guard_association.phoenix[0].id, null)
}

output "database_tier" {
  value = var.database_tier
}

output "basedb_license_model" {
  description = "License model actually applied to the basedb primary — echoes var.basedb_license_model so tests can assert the BYOL default without duplicating the resource's argument."
  value       = try(oci_database_db_system.ashburn[0].license_model, null)
}

output "ashburn_cpu_core_count" {
  value = try(oci_database_cloud_vm_cluster.ashburn[0].cpu_core_count, null)
}

output "phoenix_cpu_core_count" {
  value = try(oci_database_cloud_vm_cluster.phoenix[0].cpu_core_count, null)
}
