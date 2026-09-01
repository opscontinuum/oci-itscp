output "ashburn_vcn_id" {
  value = try(oci_core_vcn.ashburn[0].id, null)
}

output "phoenix_vcn_id" {
  value = try(oci_core_vcn.phoenix[0].id, null)
}

output "ashburn_app_subnet_ids" {
  description = "Map keyed the same as var.ashburn_app_subnets."
  value       = { for k, s in oci_core_subnet.ashburn_app : k => s.id }
}

output "phoenix_app_subnet_ids" {
  description = "Map keyed the same as var.phoenix_app_subnets."
  value       = { for k, s in oci_core_subnet.phoenix_app : k => s.id }
}

output "ashburn_app_subnet_id_list" {
  value = [for s in oci_core_subnet.ashburn_app : s.id]
}

output "phoenix_app_subnet_id_list" {
  value = [for s in oci_core_subnet.phoenix_app : s.id]
}

output "ashburn_db_subnet_id" {
  value = try(oci_core_subnet.ashburn_db[0].id, null)
}

output "ashburn_db_backup_subnet_id" {
  value = try(oci_core_subnet.ashburn_db_backup[0].id, null)
}

output "phoenix_db_subnet_id" {
  value = try(oci_core_subnet.phoenix_db[0].id, null)
}

output "phoenix_db_backup_subnet_id" {
  value = try(oci_core_subnet.phoenix_db_backup[0].id, null)
}

output "ashburn_lb_subnet_id" {
  value = try(oci_core_subnet.ashburn_lb[0].id, null)
}

output "phoenix_lb_subnet_id" {
  value = try(oci_core_subnet.phoenix_lb[0].id, null)
}

output "ashburn_app_nsg_id" {
  value = try(oci_core_network_security_group.ashburn_app[0].id, null)
}

output "ashburn_db_nsg_id" {
  value = try(oci_core_network_security_group.ashburn_db[0].id, null)
}

output "ashburn_lb_nsg_id" {
  value = try(oci_core_network_security_group.ashburn_lb[0].id, null)
}

output "phoenix_app_nsg_id" {
  value = try(oci_core_network_security_group.phoenix_app[0].id, null)
}

output "phoenix_db_nsg_id" {
  value = try(oci_core_network_security_group.phoenix_db[0].id, null)
}

output "phoenix_lb_nsg_id" {
  value = try(oci_core_network_security_group.phoenix_lb[0].id, null)
}

output "ashburn_drg_id" {
  value = try(oci_core_drg.ashburn[0].id, null)
}

output "phoenix_drg_id" {
  value = try(oci_core_drg.phoenix[0].id, null)
}

output "ashburn_dns_view_id" {
  value = try(oci_dns_view.ashburn[0].id, null)
}

output "phoenix_dns_view_id" {
  value = try(oci_dns_view.phoenix[0].id, null)
}

output "ashburn_dns_zone_id" {
  value = try(oci_dns_zone.ashburn[0].id, null)
}

output "phoenix_dns_zone_id" {
  value = try(oci_dns_zone.phoenix[0].id, null)
}
