####################################################################
# modules/network — VCNs, app/db/lb subnets, DRG + Remote Peering
# Connection, NSGs, private DNS zone + region-scoped views.
#
# Provider resource names verified against the oracle/oci Terraform
# Registry docs (fetched 2026-09-01):
#   oci_core_vcn, oci_core_subnet, oci_core_internet_gateway,
#   oci_core_route_table, oci_core_drg, oci_core_drg_attachment,
#   oci_core_remote_peering_connection, oci_core_network_security_group,
#   oci_core_network_security_group_security_rule, oci_dns_view,
#   oci_dns_zone — https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/<name>
####################################################################

terraform {
  required_providers {
    oci = {
      source                = "oracle/oci"
      configuration_aliases = [oci.ashburn, oci.phoenix]
    }
  }
}

# ---------------------------------------------------------------------------
# VCNs
# ---------------------------------------------------------------------------

resource "oci_core_vcn" "ashburn" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  cidr_blocks    = [var.ashburn_vcn_cidr]
  dns_label      = var.ashburn_vcn_dns_label
  display_name   = "vcn-ebs-iad"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_vcn" "phoenix" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  cidr_blocks    = [var.phoenix_vcn_cidr]
  dns_label      = var.phoenix_vcn_dns_label
  display_name   = "vcn-ebs-phx"
  freeform_tags  = var.freeform_tags
}

# ---------------------------------------------------------------------------
# Internet gateways + route tables for the public LB subnets (docs/01 §5.2 —
# the EBS load balancer is public-facing, behind WAF, so Traffic Management
# FAILOVER steering + Health Checks work at all).
# ---------------------------------------------------------------------------

resource "oci_core_internet_gateway" "ashburn" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.ashburn[0].id
  display_name   = "igw-ebs-iad"
  enabled        = true
}

resource "oci_core_internet_gateway" "phoenix" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.phoenix[0].id
  display_name   = "igw-ebs-phx"
  enabled        = true
}

resource "oci_core_route_table" "ashburn_lb" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.ashburn[0].id
  display_name   = "rt-ebs-lb-iad"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.ashburn[0].id
  }
}

resource "oci_core_route_table" "phoenix_lb" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.phoenix[0].id
  display_name   = "rt-ebs-lb-phx"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.phoenix[0].id
  }
}

# ---------------------------------------------------------------------------
# Subnets — app tier (per AD), database tier + backup, and public LB
# ---------------------------------------------------------------------------

resource "oci_core_subnet" "ashburn_app" {
  provider                   = oci.ashburn
  for_each                   = var.apply_unlocked ? var.ashburn_app_subnets : {}
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.ashburn[0].id
  cidr_block                 = each.value.cidr_block
  dns_label                  = each.value.dns_label
  display_name               = "sn-ebs-app-iad-${each.key}"
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "phoenix_app" {
  provider                   = oci.phoenix
  for_each                   = var.apply_unlocked ? var.phoenix_app_subnets : {}
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.phoenix[0].id
  cidr_block                 = each.value.cidr_block
  dns_label                  = each.value.dns_label
  display_name               = "sn-ebs-app-phx-${each.key}"
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "ashburn_db" {
  provider                   = oci.ashburn
  count                      = var.apply_unlocked ? 1 : 0
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.ashburn[0].id
  cidr_block                 = var.ashburn_db_subnet_cidr
  dns_label                  = "iaddb"
  display_name               = "sn-ebs-db-iad"
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "ashburn_db_backup" {
  provider                   = oci.ashburn
  count                      = var.apply_unlocked ? 1 : 0
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.ashburn[0].id
  cidr_block                 = var.ashburn_db_backup_subnet_cidr
  dns_label                  = "iaddbbkp"
  display_name               = "sn-ebs-db-backup-iad"
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "phoenix_db" {
  provider                   = oci.phoenix
  count                      = var.apply_unlocked ? 1 : 0
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.phoenix[0].id
  cidr_block                 = var.phoenix_db_subnet_cidr
  dns_label                  = "phxdb"
  display_name               = "sn-ebs-db-phx"
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "phoenix_db_backup" {
  provider                   = oci.phoenix
  count                      = var.apply_unlocked ? 1 : 0
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.phoenix[0].id
  cidr_block                 = var.phoenix_db_backup_subnet_cidr
  dns_label                  = "phxdbbkp"
  display_name               = "sn-ebs-db-backup-phx"
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "ashburn_lb" {
  provider                   = oci.ashburn
  count                      = var.apply_unlocked ? 1 : 0
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.ashburn[0].id
  cidr_block                 = var.ashburn_lb_subnet_cidr
  dns_label                  = "iadlb"
  display_name               = "sn-ebs-lb-iad"
  route_table_id             = oci_core_route_table.ashburn_lb[0].id
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_subnet" "phoenix_lb" {
  provider                   = oci.phoenix
  count                      = var.apply_unlocked ? 1 : 0
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.phoenix[0].id
  cidr_block                 = var.phoenix_lb_subnet_cidr
  dns_label                  = "phxlb"
  display_name               = "sn-ebs-lb-phx"
  route_table_id             = oci_core_route_table.phoenix_lb[0].id
  prohibit_public_ip_on_vnic = false
}

# ---------------------------------------------------------------------------
# DRG + Remote Peering Connection (docs/01-architecture.md A6 — cross-region
# traffic rides DRG + RPC over the OCI backbone, not FastConnect/Internet)
# ---------------------------------------------------------------------------

resource "oci_core_drg" "ashburn" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "drg-ebs-iad"
}

resource "oci_core_drg" "phoenix" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "drg-ebs-phx"
}

resource "oci_core_drg_attachment" "ashburn" {
  provider     = oci.ashburn
  count        = var.apply_unlocked ? 1 : 0
  display_name = "drg-attach-iad"

  network_details {
    id   = oci_core_vcn.ashburn[0].id
    type = "VCN"
  }
  drg_id = oci_core_drg.ashburn[0].id
}

resource "oci_core_drg_attachment" "phoenix" {
  provider     = oci.phoenix
  count        = var.apply_unlocked ? 1 : 0
  display_name = "drg-attach-phx"

  network_details {
    id   = oci_core_vcn.phoenix[0].id
    type = "VCN"
  }
  drg_id = oci_core_drg.phoenix[0].id
}

# Each region's Remote Peering Connection points at the other's peer_id /
# peer_region_name. Both RPCs must be applied before peering completes —
# fine for authoring, since this repo never applies.
resource "oci_core_remote_peering_connection" "ashburn" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  drg_id         = oci_core_drg.ashburn[0].id
  display_name   = "rpc-ebs-iad-to-phx"

  peer_id          = oci_core_remote_peering_connection.phoenix[0].id
  peer_region_name = "us-phoenix-1"
}

resource "oci_core_remote_peering_connection" "phoenix" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  drg_id         = oci_core_drg.phoenix[0].id
  display_name   = "rpc-ebs-phx-to-iad"

  peer_region_name = "us-ashburn-1"
}

# ---------------------------------------------------------------------------
# Network Security Groups — one app-tier, one db-tier, one lb-tier NSG per
# region, with a representative rule each. Full rule sets belong in
# checklists/ and are estate-specific; these are the shape, not the whole
# firewall design.
# ---------------------------------------------------------------------------

resource "oci_core_network_security_group" "ashburn_app" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.ashburn[0].id
  display_name   = "nsg-ebs-app-iad"
}

resource "oci_core_network_security_group" "ashburn_db" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.ashburn[0].id
  display_name   = "nsg-ebs-db-iad"
}

resource "oci_core_network_security_group" "ashburn_lb" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.ashburn[0].id
  display_name   = "nsg-ebs-lb-iad"
}

resource "oci_core_network_security_group" "phoenix_app" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.phoenix[0].id
  display_name   = "nsg-ebs-app-phx"
}

resource "oci_core_network_security_group" "phoenix_db" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.phoenix[0].id
  display_name   = "nsg-ebs-db-phx"
}

resource "oci_core_network_security_group" "phoenix_lb" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.phoenix[0].id
  display_name   = "nsg-ebs-lb-phx"
}

# App tier -> DB tier, TCP/1521 (SQL*Net)
resource "oci_core_network_security_group_security_rule" "ashburn_db_from_app" {
  provider                  = oci.ashburn
  count                     = var.apply_unlocked ? 1 : 0
  network_security_group_id = oci_core_network_security_group.ashburn_db[0].id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.ashburn_app[0].id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 1521
      max = 1521
    }
  }
}

resource "oci_core_network_security_group_security_rule" "phoenix_db_from_app" {
  provider                  = oci.phoenix
  count                     = var.apply_unlocked ? 1 : 0
  network_security_group_id = oci_core_network_security_group.phoenix_db[0].id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.phoenix_app[0].id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 1521
      max = 1521
    }
  }
}

# Public -> LB tier, TCP/443
resource "oci_core_network_security_group_security_rule" "ashburn_lb_from_internet" {
  provider                  = oci.ashburn
  count                     = var.apply_unlocked ? 1 : 0
  network_security_group_id = oci_core_network_security_group.ashburn_lb[0].id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "phoenix_lb_from_internet" {
  provider                  = oci.phoenix
  count                     = var.apply_unlocked ? 1 : 0
  network_security_group_id = oci_core_network_security_group.phoenix_lb[0].id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# ---------------------------------------------------------------------------
# Private DNS — logical host names (docs/01-architecture.md §5.1). Same zone
# name, one PRIVATE view per region, so ebsweb01/ebscm01/... resolve to
# region-local physical hosts without touching EBS context files at failover.
# ---------------------------------------------------------------------------

resource "oci_dns_view" "ashburn" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "view-ebs-logical-iad"
  scope          = "PRIVATE"
}

resource "oci_dns_view" "phoenix" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "view-ebs-logical-phx"
  scope          = "PRIVATE"
}

resource "oci_dns_zone" "ashburn" {
  provider       = oci.ashburn
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  name           = var.private_dns_zone_name
  zone_type      = "PRIMARY"
  scope          = "PRIVATE"
  view_id        = oci_dns_view.ashburn[0].id
}

resource "oci_dns_zone" "phoenix" {
  provider       = oci.phoenix
  count          = var.apply_unlocked ? 1 : 0
  compartment_id = var.compartment_id
  name           = var.private_dns_zone_name
  zone_type      = "PRIMARY"
  scope          = "PRIVATE"
  view_id        = oci_dns_view.phoenix[0].id
}
