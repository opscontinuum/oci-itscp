####################################################################
# modules/database — two selectable tiers:
#
#   exadb-d  oci_database_cloud_exadata_infrastructure +
#            oci_database_cloud_vm_cluster (docs/01 A2, the actual design)
#   basedb   oci_database_db_system (Tier-C cheap BOM alternative) +
#            oci_database_data_guard_association for the Phoenix standby
#
# Verified against oracle/oci Terraform Registry docs (fetched
# 2026-09-01):
#   oci_database_cloud_exadata_infrastructure, oci_database_cloud_vm_cluster
#     (cpu_core_count lives HERE, on the VM cluster, not the Exadata
#     infrastructure resource; node_count is computed/exported only)
#     https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/database_cloud_vm_cluster
#   oci_database_db_system — confirmed still current for Base Database
#     Service (its deprecation notice is scoped to "Exadata Cloud Service
#     systems" only: "Use the CreateCloudExadataInfrastructure and
#     CreateCloudVmCluster APIs to provision a new Exadata Cloud Service
#     instance" — that's the exadb-d tier above, not this one)
#     https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/database_db_system
#   oci_database_data_guard_association — chosen over oci_database_database
#     with source=DATAGUARD because its argument set (creation_type,
#     database_admin_password, database_id, protection_mode,
#     transport_type — all Required, fully documented) is self-contained,
#     where source=DATAGUARD instead requires standing up a whole separate
#     db_home/db_system graph for the standby's own top-level resource.
#     https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/database_data_guard_association
#   data.oci_database_db_homes, data.oci_database_databases — used to
#     resolve the primary basedb database's OCID for database_id above,
#     since oci_database_db_system exposes no top-level db_home_id/
#     database_id computed attribute.
####################################################################

terraform {
  required_providers {
    oci = {
      source                = "oracle/oci"
      configuration_aliases = [oci.ashburn, oci.phoenix]
    }
  }
}

locals {
  is_exadb  = var.apply_unlocked && var.database_tier == "exadb-d"
  is_basedb = var.apply_unlocked && var.database_tier == "basedb"
}

# ===========================================================================
# Tier: exadb-d
# ===========================================================================

resource "oci_database_cloud_exadata_infrastructure" "ashburn" {
  provider            = oci.ashburn
  count               = local.is_exadb ? 1 : 0
  compartment_id      = var.compartment_id
  availability_domain = var.ashburn_ad
  display_name        = "exainfra-ebsprod-iad"
  shape               = var.exadata_shape
  compute_count       = var.exadata_compute_count
  storage_count       = var.exadata_storage_count
  freeform_tags       = var.freeform_tags
}

resource "oci_database_cloud_exadata_infrastructure" "phoenix" {
  provider            = oci.phoenix
  count               = local.is_exadb ? 1 : 0
  compartment_id      = var.compartment_id
  availability_domain = var.phoenix_ad
  display_name        = "exainfra-ebsprod-phx"
  shape               = var.exadata_shape
  compute_count       = var.exadata_compute_count
  storage_count       = var.exadata_storage_count
  freeform_tags       = var.freeform_tags
}

resource "oci_database_cloud_vm_cluster" "ashburn" {
  provider                        = oci.ashburn
  count                           = local.is_exadb ? 1 : 0
  compartment_id                  = var.compartment_id
  cloud_exadata_infrastructure_id = oci_database_cloud_exadata_infrastructure.ashburn[0].id
  display_name                    = "vmcluster-ebsprod-iad"
  hostname                        = "ebsprodiad"
  gi_version                      = var.gi_version
  cpu_core_count                  = var.ashburn_cpu_core_count
  ssh_public_keys                 = var.ssh_public_keys
  subnet_id                       = var.ashburn_db_subnet_id
  backup_subnet_id                = var.ashburn_db_backup_subnet_id
  freeform_tags                   = var.freeform_tags
}

resource "oci_database_cloud_vm_cluster" "phoenix" {
  provider                        = oci.phoenix
  count                           = local.is_exadb ? 1 : 0
  compartment_id                  = var.compartment_id
  cloud_exadata_infrastructure_id = oci_database_cloud_exadata_infrastructure.phoenix[0].id
  display_name                    = "vmcluster-ebsprod-phx"
  hostname                        = "ebsprodphx"
  gi_version                      = var.gi_version
  # OCPU floor posture — never 0 (docs/05 §2: scaling to 0 shuts the whole
  # VM cluster down and silently converts Tier 1 into Tier 3).
  cpu_core_count   = var.phoenix_cpu_core_count
  ssh_public_keys  = var.ssh_public_keys
  subnet_id        = var.phoenix_db_subnet_id
  backup_subnet_id = var.phoenix_db_backup_subnet_id
  freeform_tags    = var.freeform_tags
}

# ===========================================================================
# Tier: basedb (Tier-C cheap alternative)
# ===========================================================================

resource "oci_database_db_system" "ashburn" {
  provider                = oci.ashburn
  count                   = local.is_basedb ? 1 : 0
  compartment_id          = var.compartment_id
  availability_domain     = var.ashburn_ad
  subnet_id               = var.ashburn_db_subnet_id
  shape                   = var.basedb_shape
  hostname                = "ebsprodiad"
  ssh_public_keys         = var.ssh_public_keys
  database_edition        = "ENTERPRISE_EDITION"
  license_model           = var.basedb_license_model
  node_count              = 1
  data_storage_size_in_gb = var.basedb_data_storage_size_gb
  freeform_tags           = var.freeform_tags

  db_home {
    db_version = var.basedb_db_version

    database {
      admin_password = var.basedb_admin_password
      db_name        = var.basedb_db_name
    }
  }

  lifecycle {
    ignore_changes = [db_home[0].database[0].admin_password]
  }
}

data "oci_database_db_homes" "ashburn" {
  count          = local.is_basedb ? 1 : 0
  compartment_id = var.compartment_id
  db_system_id   = oci_database_db_system.ashburn[0].id
}

data "oci_database_databases" "ashburn" {
  count          = local.is_basedb ? 1 : 0
  compartment_id = var.compartment_id
  db_home_id     = data.oci_database_db_homes.ashburn[0].db_homes[0].id
}

# Phoenix standby, via oci_database_data_guard_association
# (creation_type=NewDbSystem) rather than a second oci_database_db_system —
# RB-05 Phase 2 requires standbys to be created through the control plane so
# Full Stack DR prechecks see them (docs/01 §3).
#
# CAVEAT — read before using this tier for anything beyond the BOM/cost
# estimator: neither this resource's Terraform Registry page nor
# oci_database_database's source=DATAGUARD path documents an explicit
# cross-region/peer-region argument for standby placement (grepped both
# full pages for "region" — no cross-region standby-placement field on
# either). Whether Base Database Service Data Guard associations created
# through this classic API can place the standby in a different region's
# subnet than the primary was NOT confirmed in this revision. This is
# exactly the gap docs/01-architecture.md A2 designs around by requiring
# ExaDB-D (whose cross-region standby path is the proven one, docs/01 §3)
# for the real environment. Validate against the OCI Database API reference and
# a real tenancy before relying on cross-region basedb Data Guard.
resource "oci_database_data_guard_association" "phoenix" {
  provider                         = oci.ashburn
  count                            = local.is_basedb ? 1 : 0
  database_id                      = data.oci_database_databases.ashburn[0].databases[0].id
  creation_type                    = "NewDbSystem"
  database_admin_password          = var.basedb_admin_password
  delete_standby_db_home_on_delete = true
  protection_mode                  = var.basedb_data_guard_protection_mode
  transport_type                   = var.basedb_data_guard_transport_type

  availability_domain = var.phoenix_ad
  hostname            = "ebsprodphx"
  shape               = var.basedb_shape
  subnet_id           = var.phoenix_db_subnet_id
  node_count          = 1
  license_model       = var.basedb_license_model
}
