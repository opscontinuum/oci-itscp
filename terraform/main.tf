####################################################################
# main.tf — root module composition.
#
# Apply lock enforcement: `terraform_data.apply_lock_guard` is a
# built-in resource (terraform.io/builtin/terraform — no OCI
# credentials, no provider block needed) that always exists. Its
# lifecycle precondition passes trivially in the default LOCKED state
# (unlock_apply = false) — that is the safe, expected posture this
# repository ships in, and `terraform validate` / `terraform test`
# must succeed against it. It only fails loudly, with the reason, if
# someone sets unlock_apply = true without also supplying the exact
# spend_acknowledgement phrase: an attempted-but-incomplete unlock.
# See terraform/README.md "Apply lock".
####################################################################

resource "terraform_data" "apply_lock_guard" {
  input = local.apply_unlocked

  lifecycle {
    precondition {
      condition     = !var.unlock_apply || local.apply_unlocked
      error_message = <<-EOT
        unlock_apply = true but spend_acknowledgement does not match.
        Set spend_acknowledgement_duration (e.g. "8h") and
        spend_acknowledgement exactly to:
          "I accept the estimated cost for <spend_acknowledgement_duration>"
        Review the BOM first: terraform output bom
        This is the Tier-C "author only, never apply" posture — see
        terraform/README.md.
      EOT
    }
  }
}

# Non-blocking, informational: a warning-level check (check blocks never
# hard-fail terraform plan/apply, by Terraform design since 1.5 — but
# `terraform test` DOES report a failed check assertion as a run failure,
# so this condition mirrors the precondition above and only fires for a
# genuine misconfigured-unlock attempt, never for the safe default LOCKED
# state that every other test run exercises).
check "apply_lock_posture" {
  assert {
    condition     = !var.unlock_apply || local.apply_unlocked
    error_message = "unlock_apply = true but spend_acknowledgement does not match the required phrase. See terraform/README.md \"Apply lock\"."
  }
}

# ---------------------------------------------------------------------------
# Node topology — the environment's physical/logical host name map (docs/01 §2,
# §5.1). Physical names are unique per region+AD; logical names are the
# same in both regions and resolved region-locally via modules/network's
# private DNS views.
# ---------------------------------------------------------------------------

locals {
  windows_shape      = "VM.Standard.E5.Flex"
  windows_ocpus      = 1
  windows_memory_gbs = 8
  windows_boot_gbs   = 50
  windows_data_gbs   = 120 # 5 Ashburn nodes x 120 GB ~= 600 GB (BOM)

  ashburn_instances = {
    "IAD-EBSWEB01" = {
      availability_domain  = var.ashburn_ad1
      subnet_id            = try(module.network.ashburn_app_subnet_ids["ad1"], null)
      role                 = "web"
      logical_hostname     = "ebsweb01"
      shape                = local.windows_shape
      ocpus                = local.windows_ocpus
      memory_in_gbs        = local.windows_memory_gbs
      boot_volume_size_gbs = local.windows_boot_gbs
      data_volume_size_gbs = local.windows_data_gbs
      initial_state        = "RUNNING"
      nsg_ids              = [module.network.ashburn_app_nsg_id]
    }
    "IAD-EBSWEB02" = {
      availability_domain  = var.ashburn_ad2
      subnet_id            = try(module.network.ashburn_app_subnet_ids["ad2"], null)
      role                 = "web"
      logical_hostname     = "ebsweb02"
      shape                = local.windows_shape
      ocpus                = local.windows_ocpus
      memory_in_gbs        = local.windows_memory_gbs
      boot_volume_size_gbs = local.windows_boot_gbs
      data_volume_size_gbs = local.windows_data_gbs
      initial_state        = "RUNNING"
      nsg_ids              = [module.network.ashburn_app_nsg_id]
    }
    "IAD-EBSCM01" = {
      availability_domain  = var.ashburn_ad1
      subnet_id            = try(module.network.ashburn_app_subnet_ids["ad1"], null)
      role                 = "cm"
      logical_hostname     = "ebscm01"
      shape                = local.windows_shape
      ocpus                = local.windows_ocpus
      memory_in_gbs        = local.windows_memory_gbs
      boot_volume_size_gbs = local.windows_boot_gbs
      data_volume_size_gbs = local.windows_data_gbs
      initial_state        = "RUNNING"
      nsg_ids              = [module.network.ashburn_app_nsg_id]
    }
    "IAD-EBSCM02" = {
      availability_domain  = var.ashburn_ad2
      subnet_id            = try(module.network.ashburn_app_subnet_ids["ad2"], null)
      role                 = "cm"
      logical_hostname     = "ebscm02"
      shape                = local.windows_shape
      ocpus                = local.windows_ocpus
      memory_in_gbs        = local.windows_memory_gbs
      boot_volume_size_gbs = local.windows_boot_gbs
      data_volume_size_gbs = local.windows_data_gbs
      initial_state        = "STOPPED" # AD-2 concurrent-manager twin — stopped (README brief / docs/01 §2)
      nsg_ids              = [module.network.ashburn_app_nsg_id]
    }
    "IAD-BI01" = {
      availability_domain  = var.ashburn_ad2
      subnet_id            = try(module.network.ashburn_app_subnet_ids["ad2"], null)
      role                 = "bi"
      logical_hostname     = "ebsbi01"
      shape                = local.windows_shape
      ocpus                = local.windows_ocpus
      memory_in_gbs        = local.windows_memory_gbs
      boot_volume_size_gbs = local.windows_boot_gbs
      data_volume_size_gbs = local.windows_data_gbs
      initial_state        = "RUNNING"
      nsg_ids              = [module.network.ashburn_app_nsg_id]
    }
  }

  phoenix_instances = {
    "PHX-EBSWEB01" = {
      availability_domain  = var.phoenix_ad1
      subnet_id            = try(module.network.phoenix_app_subnet_ids["ad1"], null)
      role                 = "web"
      logical_hostname     = "ebsweb01"
      shape                = local.windows_shape
      ocpus                = local.windows_ocpus
      memory_in_gbs        = local.windows_memory_gbs
      boot_volume_size_gbs = local.windows_boot_gbs
      initial_state        = "STOPPED"
      nsg_ids              = [module.network.phoenix_app_nsg_id]
    }
    "PHX-EBSWEB02" = {
      availability_domain  = var.phoenix_ad1
      subnet_id            = try(module.network.phoenix_app_subnet_ids["ad1"], null)
      role                 = "web"
      logical_hostname     = "ebsweb02"
      shape                = local.windows_shape
      ocpus                = local.windows_ocpus
      memory_in_gbs        = local.windows_memory_gbs
      boot_volume_size_gbs = local.windows_boot_gbs
      initial_state        = "STOPPED"
      nsg_ids              = [module.network.phoenix_app_nsg_id]
    }
    "PHX-EBSCM01" = {
      availability_domain  = var.phoenix_ad1
      subnet_id            = try(module.network.phoenix_app_subnet_ids["ad1"], null)
      role                 = "cm"
      logical_hostname     = "ebscm01"
      shape                = local.windows_shape
      ocpus                = local.windows_ocpus
      memory_in_gbs        = local.windows_memory_gbs
      boot_volume_size_gbs = local.windows_boot_gbs
      initial_state        = "STOPPED"
      nsg_ids              = [module.network.phoenix_app_nsg_id]
    }
    "PHX-EBSCM02" = {
      availability_domain  = var.phoenix_ad1
      subnet_id            = try(module.network.phoenix_app_subnet_ids["ad1"], null)
      role                 = "cm"
      logical_hostname     = "ebscm02"
      shape                = local.windows_shape
      ocpus                = local.windows_ocpus
      memory_in_gbs        = local.windows_memory_gbs
      boot_volume_size_gbs = local.windows_boot_gbs
      initial_state        = "STOPPED"
      nsg_ids              = [module.network.phoenix_app_nsg_id]
    }
    "PHX-BI01" = {
      availability_domain  = var.phoenix_ad1
      subnet_id            = try(module.network.phoenix_app_subnet_ids["ad1"], null)
      role                 = "bi"
      logical_hostname     = "ebsbi01"
      shape                = local.windows_shape
      ocpus                = local.windows_ocpus
      memory_in_gbs        = local.windows_memory_gbs
      boot_volume_size_gbs = local.windows_boot_gbs
      initial_state        = "RUNNING" # always on — reads the ADG standby (docs/01 §4.5)
      nsg_ids              = [module.network.phoenix_app_nsg_id]
    }
  }
}

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------

module "network" {
  source = "./modules/network"

  providers = {
    oci.ashburn = oci.ashburn
    oci.phoenix = oci.phoenix
  }

  apply_unlocked = local.apply_unlocked
  compartment_id = var.compartment_id
  freeform_tags  = var.freeform_tags
}

module "compute" {
  source = "./modules/compute"

  providers = {
    oci.ashburn = oci.ashburn
    oci.phoenix = oci.phoenix
  }

  apply_unlocked    = local.apply_unlocked
  compartment_id    = var.compartment_id
  freeform_tags     = var.freeform_tags
  windows_image_id  = var.windows_image_id
  ashburn_instances = local.ashburn_instances
  phoenix_instances = local.phoenix_instances

  phoenix_replica_availability_domain = var.phoenix_ad1
}

module "storage" {
  source = "./modules/storage"

  providers = {
    oci.ashburn = oci.ashburn
    oci.phoenix = oci.phoenix
  }

  apply_unlocked           = local.apply_unlocked
  compartment_id           = var.compartment_id
  freeform_tags            = var.freeform_tags
  object_storage_namespace = var.object_storage_namespace

  ashburn_fss_availability_domain = var.ashburn_ad1
  phoenix_fss_availability_domain = var.phoenix_ad1
  ashburn_fss_subnet_id           = try(module.network.ashburn_app_subnet_ids["ad1"], null)
  phoenix_fss_subnet_id           = try(module.network.phoenix_app_subnet_ids["ad1"], null)
}

module "lb" {
  source = "./modules/lb"

  providers = {
    oci.ashburn = oci.ashburn
    oci.phoenix = oci.phoenix
  }

  apply_unlocked       = local.apply_unlocked
  compartment_id       = var.compartment_id
  freeform_tags        = var.freeform_tags
  ashburn_lb_subnet_id = module.network.ashburn_lb_subnet_id
  phoenix_lb_subnet_id = module.network.phoenix_lb_subnet_id
  ashburn_lb_nsg_id    = module.network.ashburn_lb_nsg_id
  phoenix_lb_nsg_id    = module.network.phoenix_lb_nsg_id
}

module "dns" {
  source = "./modules/dns"

  providers = {
    oci.ashburn = oci.ashburn
    oci.phoenix = oci.phoenix
  }

  apply_unlocked = local.apply_unlocked
  compartment_id = var.compartment_id
  freeform_tags  = var.freeform_tags
}

module "database" {
  source = "./modules/database"

  providers = {
    oci.ashburn = oci.ashburn
    oci.phoenix = oci.phoenix
  }

  apply_unlocked        = local.apply_unlocked
  compartment_id        = var.compartment_id
  freeform_tags         = var.freeform_tags
  database_tier         = var.database_tier
  ashburn_ad            = var.ashburn_ad1
  phoenix_ad            = var.phoenix_ad1
  ssh_public_keys       = var.ssh_public_keys
  basedb_admin_password = var.basedb_admin_password

  ashburn_db_subnet_id        = module.network.ashburn_db_subnet_id
  ashburn_db_backup_subnet_id = module.network.ashburn_db_backup_subnet_id
  phoenix_db_subnet_id        = module.network.phoenix_db_subnet_id
  phoenix_db_backup_subnet_id = module.network.phoenix_db_backup_subnet_id
}

module "recovery" {
  source = "./modules/recovery"

  providers = {
    oci.ashburn = oci.ashburn
  }

  apply_unlocked              = local.apply_unlocked
  compartment_id              = var.compartment_id
  freeform_tags               = var.freeform_tags
  ashburn_vcn_id              = module.network.ashburn_vcn_id
  ashburn_recovery_subnet_ids = module.network.ashburn_app_subnet_id_list
  primary_database_id         = module.database.ashburn_primary_database_id
  protected_database_password = var.protected_database_password
}

module "monitoring" {
  source = "./modules/monitoring"

  providers = {
    oci.ashburn = oci.ashburn
  }

  apply_unlocked                     = local.apply_unlocked
  compartment_id                     = var.compartment_id
  freeform_tags                      = var.freeform_tags
  volume_replica_resource_id         = "" # populate from terraform/dr-resources.env post-build (DR_VOLUME_GROUP_REPLICA_OCIDS)
  fss_replication_target_resource_id = "" # populate from DR_FSS_REPLICATION_OCIDS
  # The OCPU-floor alarm only means something for the exadb-d tier (basedb
  # has no VM cluster, so phoenix_vm_cluster_id is null there) — and
  # module.database.phoenix_vm_cluster_id is also null in the default
  # LOCKED state regardless of tier. coalesce() treats "" as unusable too
  # (it errors with "no non-null, non-empty-string arguments" if every
  # candidate is null/""), so the fallback below must be a non-empty
  # placeholder string, not "".
  phoenix_vm_cluster_resource_id = coalesce(module.database.phoenix_vm_cluster_id, "unset")
  phoenix_vm_cluster_ocpu_floor  = var.database_tier == "exadb-d" ? 4 : 2
}

module "scheduler" {
  source = "./modules/scheduler"

  providers = {
    oci.phoenix = oci.phoenix
  }

  apply_unlocked                 = local.apply_unlocked
  compartment_id                 = var.compartment_id
  freeform_tags                  = var.freeform_tags
  stoppable_phoenix_instance_ids = module.compute.stoppable_phoenix_instance_ids
}

module "fsdr" {
  source = "./modules/fsdr"

  providers = {
    oci.ashburn = oci.ashburn
    oci.phoenix = oci.phoenix
  }

  apply_unlocked           = local.apply_unlocked
  compartment_id           = var.compartment_id
  freeform_tags            = var.freeform_tags
  object_storage_namespace = var.object_storage_namespace
  ashburn_log_bucket       = module.storage.fsdr_log_bucket_ashburn_name
  phoenix_log_bucket       = module.storage.fsdr_log_bucket_phoenix_name

  ashburn_members = concat(
    [for k, id in module.compute.ashburn_instance_ids : { member_id = id, member_type = "COMPUTE_INSTANCE_NON_MOVABLE" }],
    [for k, id in module.compute.ashburn_volume_group_ids : { member_id = id, member_type = "VOLUME_GROUP" }],
    module.storage.ashburn_file_system_id == null ? [] : [{ member_id = module.storage.ashburn_file_system_id, member_type = "FILE_SYSTEM" }],
    [for k, id in module.storage.ashburn_bucket_ids : { member_id = id, member_type = "OBJECT_STORAGE_BUCKET" }],
    module.lb.ashburn_lb_id == null ? [] : [{ member_id = module.lb.ashburn_lb_id, member_type = "LOAD_BALANCER" }],
    # The exadb-d tier's actual pluggable/container database OCID is not
    # provisioned by this Terraform (Oracle's EBS clone process creates it
    # via DBCA/RMAN duplicate against the VM cluster, RB-05 Phase 2/4, not
    # a first-class `oci_database_database` resource in this codebase) —
    # supply it out-of-band via dr-resources.env's PRIMARY_DATABASE_OCID
    # and add a DATABASE member manually, or switch database_tier to
    # "basedb" to get a Terraform-managed database OCID automatically.
    var.database_tier == "basedb" && module.database.ashburn_primary_database_id != null ? [
      { member_id = module.database.ashburn_primary_database_id, member_type = "DATABASE" }
    ] : []
  )

  phoenix_members = concat(
    [for k, id in module.compute.phoenix_instance_ids : { member_id = id, member_type = "COMPUTE_INSTANCE_NON_MOVABLE" }],
    module.storage.phoenix_file_system_id == null ? [] : [{ member_id = module.storage.phoenix_file_system_id, member_type = "FILE_SYSTEM" }],
    [for k, id in module.storage.phoenix_bucket_ids : { member_id = id, member_type = "OBJECT_STORAGE_BUCKET" }],
    module.lb.phoenix_lb_id == null ? [] : [{ member_id = module.lb.phoenix_lb_id, member_type = "LOAD_BALANCER" }],
  )
}
