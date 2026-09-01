output "ashburn_lb_id" {
  value = try(oci_load_balancer_load_balancer.ashburn[0].id, null)
}

output "phoenix_lb_id" {
  value = try(oci_load_balancer_load_balancer.phoenix[0].id, null)
}

output "ashburn_lb_ip_addresses" {
  value = try(oci_load_balancer_load_balancer.ashburn[0].ip_address_details, null)
}

output "phoenix_lb_ip_addresses" {
  value = try(oci_load_balancer_load_balancer.phoenix[0].ip_address_details, null)
}

output "ashburn_backend_set_name" {
  value = try(oci_load_balancer_backend_set.ashburn[0].name, null)
}

output "phoenix_backend_set_name" {
  value = try(oci_load_balancer_backend_set.phoenix[0].name, null)
}
