####################################################################
# modules/dns — OCI Traffic Management FAILOVER steering policy +
# Health Checks (docs/01 §5.2, docs/03 R8). Requires a PUBLIC DNS
# zone — Traffic Management "is only available for public DNS" —
# supplied via var.public_zone_id, not created here.
#
# Verified against oracle/oci Terraform Registry docs (fetched
# 2026-09-01): oci_dns_steering_policy (template="FAILOVER"; rule
# order FILTER -> HEALTH -> PRIORITY -> LIMIT is REQUIRED by the
# template: "All templates require the rule order to begin with an
# unconditional FILTER rule... A defined HEALTH rule must follow the
# FILTER rule if the policy references a healthCheckMonitorId. The
# last rule of a template must be a LIMIT rule."), oci_dns_steering_
# policy_attachment, oci_health_checks_http_monitor.
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/dns_steering_policy
#
# The exact PRIORITY-rule answer_condition/value combination that
# reliably ranks one pool ahead of another beyond this shape was not
# spelled out in a full worked FAILOVER example on the provider docs
# page — validate the rendered policy in the OCI console against a
# real health check before relying on it operationally.
####################################################################

terraform {
  required_providers {
    oci = {
      source                = "oracle/oci"
      configuration_aliases = [oci.ashburn, oci.phoenix]
    }
  }
}

resource "oci_health_checks_http_monitor" "ashburn" {
  provider            = oci.ashburn
  count               = var.apply_unlocked ? 1 : 0
  compartment_id      = var.compartment_id
  display_name        = "hc-ebs-iad"
  protocol            = "HTTPS"
  targets             = var.ashburn_health_check_targets
  interval_in_seconds = 30
  freeform_tags       = var.freeform_tags
}

resource "oci_dns_steering_policy" "failover" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "sp-ebs-failover"
  template       = "FAILOVER"
  ttl            = var.ttl_seconds

  health_check_monitor_id = oci_health_checks_http_monitor.ashburn[0].id

  answers {
    name  = "ashburn-lb"
    rtype = "A"
    rdata = var.ashburn_lb_ip
    pool  = "primary"
  }

  answers {
    name  = "phoenix-lb"
    rtype = "A"
    rdata = var.phoenix_lb_ip
    pool  = "secondary"
  }

  rules {
    rule_type = "FILTER"

    default_answer_data {
      answer_condition = "answer.isDisabled != true"
      should_keep      = true
    }
  }

  rules {
    rule_type = "HEALTH"
  }

  rules {
    rule_type = "PRIORITY"

    default_answer_data {
      answer_condition = "answer.pool == 'primary'"
      value            = 0
    }
  }

  rules {
    rule_type     = "LIMIT"
    default_count = 1
  }
}

resource "oci_dns_steering_policy_attachment" "failover" {
  provider           = oci.ashburn
  count              = var.apply_unlocked ? 1 : 0
  steering_policy_id = oci_dns_steering_policy.failover[0].id
  zone_id            = var.public_zone_id
  domain_name        = var.domain_name
}
