####################################################################
# modules/lb — flexible, public load balancer per region, spanning
# both ADs (docs/01 §5.2 — EBS entry point is public-facing, behind
# WAF, which is what makes Traffic Management + Health Checks work).
#
# Verified against oracle/oci Terraform Registry docs (fetched
# 2026-09-01): oci_load_balancer_load_balancer (shape="flexible" +
# shape_details{minimum_bandwidth_in_mbps,maximum_bandwidth_in_mbps};
# is_private=false is public and is also the default),
# oci_load_balancer_backend_set, oci_load_balancer_backend,
# oci_load_balancer_listener, oci_waf_web_app_firewall +
# oci_waf_web_app_firewall_policy (real, current resources — NOT a
# null_resource placeholder; the "WAF placeholder" nature is that the
# policy below is intentionally empty of rules, since real WAF rules
# are environment-specific business logic).
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/load_balancer_load_balancer
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/waf_web_app_firewall_policy
####################################################################

terraform {
  required_providers {
    oci = {
      source                = "oracle/oci"
      configuration_aliases = [oci.ashburn, oci.phoenix]
    }
  }
}

resource "oci_load_balancer_load_balancer" "ashburn" {
  provider                   = oci.ashburn
  count                      = var.apply_unlocked ? 1 : 0
  compartment_id             = var.compartment_id
  display_name               = "lb-ebs-iad"
  shape                      = "flexible"
  subnet_ids                 = [var.ashburn_lb_subnet_id]
  is_private                 = false
  network_security_group_ids = var.ashburn_lb_nsg_id == "" ? null : [var.ashburn_lb_nsg_id]
  freeform_tags              = var.freeform_tags

  shape_details {
    minimum_bandwidth_in_mbps = var.min_bandwidth_mbps
    maximum_bandwidth_in_mbps = var.max_bandwidth_mbps
  }
}

resource "oci_load_balancer_load_balancer" "phoenix" {
  provider                   = oci.phoenix
  count                      = var.apply_unlocked ? 1 : 0
  compartment_id             = var.compartment_id
  display_name               = "lb-ebs-phx"
  shape                      = "flexible"
  subnet_ids                 = [var.phoenix_lb_subnet_id]
  is_private                 = false
  network_security_group_ids = var.phoenix_lb_nsg_id == "" ? null : [var.phoenix_lb_nsg_id]
  freeform_tags              = var.freeform_tags

  shape_details {
    minimum_bandwidth_in_mbps = var.min_bandwidth_mbps
    maximum_bandwidth_in_mbps = var.max_bandwidth_mbps
  }
}

resource "oci_load_balancer_backend_set" "ashburn" {
  provider         = oci.ashburn
  count            = var.apply_unlocked ? 1 : 0
  load_balancer_id = oci_load_balancer_load_balancer.ashburn[0].id
  name             = "ebs-web-backendset"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol    = "HTTPS"
    port        = var.backend_port
    url_path    = "/OA_HTML/AppsLogin"
    return_code = 200
  }
}

resource "oci_load_balancer_backend_set" "phoenix" {
  provider         = oci.phoenix
  count            = var.apply_unlocked ? 1 : 0
  load_balancer_id = oci_load_balancer_load_balancer.phoenix[0].id
  name             = "ebs-web-backendset"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol    = "HTTPS"
    port        = var.backend_port
    url_path    = "/OA_HTML/AppsLogin"
    return_code = 200
  }
}

resource "oci_load_balancer_backend" "ashburn" {
  provider         = oci.ashburn
  for_each         = var.apply_unlocked ? toset(var.ashburn_backend_ip_addresses) : []
  load_balancer_id = oci_load_balancer_load_balancer.ashburn[0].id
  backendset_name  = oci_load_balancer_backend_set.ashburn[0].name
  ip_address       = each.key
  port             = var.backend_port
}

resource "oci_load_balancer_backend" "phoenix" {
  provider         = oci.phoenix
  for_each         = var.apply_unlocked ? toset(var.phoenix_backend_ip_addresses) : []
  load_balancer_id = oci_load_balancer_load_balancer.phoenix[0].id
  backendset_name  = oci_load_balancer_backend_set.phoenix[0].name
  ip_address       = each.key
  port             = var.backend_port
}

resource "oci_load_balancer_listener" "ashburn" {
  provider                 = oci.ashburn
  count                    = var.apply_unlocked ? 1 : 0
  load_balancer_id         = oci_load_balancer_load_balancer.ashburn[0].id
  name                     = "ebs-web-listener"
  default_backend_set_name = oci_load_balancer_backend_set.ashburn[0].name
  port                     = 443
  protocol                 = "HTTP"
}

resource "oci_load_balancer_listener" "phoenix" {
  provider                 = oci.phoenix
  count                    = var.apply_unlocked ? 1 : 0
  load_balancer_id         = oci_load_balancer_load_balancer.phoenix[0].id
  name                     = "ebs-web-listener"
  default_backend_set_name = oci_load_balancer_backend_set.phoenix[0].name
  port                     = 443
  protocol                 = "HTTP"
}

# ---------------------------------------------------------------------------
# WAF — empty/minimal policies attached to each region's LB. The absence of
# rules is the deliberate "placeholder": real WAF rule content is business
# logic specific to the EBS environment and does not belong hard-coded in a
# public worked example.
# ---------------------------------------------------------------------------

resource "oci_waf_web_app_firewall_policy" "ashburn" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "waf-policy-ebs-iad-placeholder"
  freeform_tags  = var.freeform_tags
}

resource "oci_waf_web_app_firewall_policy" "phoenix" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "waf-policy-ebs-phx-placeholder"
  freeform_tags  = var.freeform_tags
}

resource "oci_waf_web_app_firewall" "ashburn" {
  provider                   = oci.ashburn
  count                      = var.apply_unlocked ? 1 : 0
  compartment_id             = var.compartment_id
  display_name               = "waf-ebs-iad"
  backend_type               = "LOAD_BALANCER"
  load_balancer_id           = oci_load_balancer_load_balancer.ashburn[0].id
  web_app_firewall_policy_id = oci_waf_web_app_firewall_policy.ashburn[0].id
  freeform_tags              = var.freeform_tags
}

resource "oci_waf_web_app_firewall" "phoenix" {
  provider                   = oci.phoenix
  count                      = var.apply_unlocked ? 1 : 0
  compartment_id             = var.compartment_id
  display_name               = "waf-ebs-phx"
  backend_type               = "LOAD_BALANCER"
  load_balancer_id           = oci_load_balancer_load_balancer.phoenix[0].id
  web_app_firewall_policy_id = oci_waf_web_app_firewall_policy.phoenix[0].id
  freeform_tags              = var.freeform_tags
}
