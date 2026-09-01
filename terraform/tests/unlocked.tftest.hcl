# Apply lock released, with a correctly-matching spend acknowledgement.
# Still no credentials required — every oci provider configuration is
# mocked, so plan proceeds using mocked computed attributes while every
# argument WE set (shapes, states, license models, plugin config, ...) is
# checked as-authored.
mock_provider "oci" {}

mock_provider "oci" {
  alias = "ashburn"
}

mock_provider "oci" {
  alias = "phoenix"
}

variables {
  unlock_apply                   = true
  spend_acknowledgement_duration = "8h"
  spend_acknowledgement          = "I accept the estimated cost for 8h"
  compartment_id                 = "ocid1.compartment.oc1..aaaaaaaatestcompartment"
  windows_image_id               = "ocid1.image.oc1.iad.aaaaaaaatestimage"
  ssh_public_keys                = ["ssh-rsa AAAAtest test@example.com"]
}

run "exadb_d_unlocked_expected_resources" {
  # apply (against the fully mocked provider — never a real tenancy) so
  # provider-computed attributes like resource `id` are known values this
  # run can assert on, not just the plan-known arguments we set ourselves.
  command = apply

  # database_tier left at its default: "exadb-d"

  assert {
    condition     = output.apply_lock_status == "UNLOCKED — resources will plan/apply"
    error_message = "apply_lock_status did not report UNLOCKED."
  }

  # 5 Ashburn + 5 Phoenix windows instances (docs/01 §2)
  assert {
    condition     = length(module.compute.ashburn_instance_ids) == 5 && length(module.compute.phoenix_instance_ids) == 5
    error_message = "expected exactly 5 Ashburn and 5 Phoenix windows instances."
  }

  # IAD-EBSCM02 stopped, everything else in Ashburn running
  assert {
    condition     = module.compute.ashburn_instance_states["IAD-EBSCM02"] == "STOPPED"
    error_message = "IAD-EBSCM02 must be STOPPED."
  }
  assert {
    condition = alltrue([
      for k, s in module.compute.ashburn_instance_states : s == "RUNNING" if k != "IAD-EBSCM02"
    ])
    error_message = "every Ashburn instance except IAD-EBSCM02 must be RUNNING."
  }

  # BI instance excluded from the stop schedule; only PHX-BI01 is always-on
  assert {
    condition     = length(module.compute.always_on_phoenix_instance_ids) == 1
    error_message = "exactly one Phoenix instance (the BI node) should be always-on."
  }
  assert {
    condition     = length(module.compute.stoppable_phoenix_instance_ids) == 4
    error_message = "the other 4 Phoenix instances should be stoppable (excludes BI)."
  }
  assert {
    condition     = module.scheduler.warm_posture_stop_schedule_id != null
    error_message = "WARM-posture stop schedule should exist when unlocked."
  }

  # Run Command plugin enabled on every instance (docs/01 §6)
  assert {
    condition     = alltrue([for k, s in module.compute.ashburn_run_command_plugin_states : s == "ENABLED"])
    error_message = "Run Command plugin must be ENABLED on every Ashburn instance."
  }
  assert {
    condition     = alltrue([for k, s in module.compute.phoenix_run_command_plugin_states : s == "ENABLED"])
    error_message = "Run Command plugin must be ENABLED on every Phoenix instance."
  }

  # cpu_core_count >= 2 per node on both VM clusters (docs/05 §2 floor)
  assert {
    condition     = module.database.ashburn_cpu_core_count >= 4 # exadb_node_count default 2 x floor 2
    error_message = "Ashburn VM cluster cpu_core_count must be >= 2 per node."
  }
  assert {
    condition     = module.database.phoenix_cpu_core_count >= 4
    error_message = "Phoenix VM cluster cpu_core_count must be >= 2 per node (never 0 — docs/05 §2)."
  }

  # FSDR: DRPG pair + 4 plans
  assert {
    condition     = module.fsdr.ashburn_drpg_id != null && module.fsdr.phoenix_drpg_id != null
    error_message = "expected a DR Protection Group pair when unlocked."
  }
  assert {
    condition = (
      module.fsdr.plan_ids.switchover != null &&
      module.fsdr.plan_ids.failover != null &&
      module.fsdr.plan_ids.start_drill != null &&
      module.fsdr.plan_ids.stop_drill != null
    )
    error_message = "expected all 4 DR plan types (switchover, failover, start_drill, stop_drill)."
  }

  # FSDR log buckets: Standard tier, and NOT part of the replicated set
  assert {
    condition     = module.storage.fsdr_log_bucket_storage_tiers.ashburn == "Standard" && module.storage.fsdr_log_bucket_storage_tiers.phoenix == "Standard"
    error_message = "FSDR log buckets must be Standard tier."
  }
  assert {
    condition     = module.storage.interchange_bucket_count == 2 && module.storage.replication_policy_count == 2
    error_message = "expected exactly 2 replicated interchange buckets (ebs-interfaces, ebs-archive) and 2 replication policies — the FSDR log buckets must not be among them."
  }

  # Recovery Service — retention lock disabled by default
  assert {
    condition     = module.recovery.retention_lock_enabled == false
    error_message = "retention_lock_enabled must default to false."
  }
}

run "basedb_tier_byol_default" {
  command = apply

  variables {
    database_tier               = "basedb"
    basedb_admin_password       = "Test_Passw0rd_12"
    protected_database_password = "Test_Passw0rd_34" # unused directly here, kept for symmetry
  }

  # The mock oci provider returns empty lists for data sources with no
  # overridden values. modules/database resolves the basedb primary
  # database's OCID through two chained data sources
  # (oci_database_db_homes -> oci_database_databases); both need a mocked
  # non-empty result here or the module's own [0] index errors out — this
  # is purely a test-harness fixture, not a change to the module's logic.
  override_data {
    target = module.database.data.oci_database_db_homes.ashburn
    values = {
      db_homes = [
        { id = "ocid1.dbhome.oc1.iad.mocktesthome" }
      ]
    }
  }

  override_data {
    target = module.database.data.oci_database_databases.ashburn
    values = {
      databases = [
        { id = "ocid1.database.oc1.iad.mocktestdatabase" }
      ]
    }
  }

  assert {
    condition     = module.database.basedb_license_model == "BRING_YOUR_OWN_LICENSE"
    error_message = "basedb tier must default to BRING_YOUR_OWN_LICENSE (docs/05 §4)."
  }
  assert {
    condition     = module.database.ashburn_db_system_id != null
    error_message = "expected a basedb db_system when database_tier = basedb and unlocked."
  }
  assert {
    condition     = module.database.ashburn_vm_cluster_id == null && module.database.phoenix_vm_cluster_id == null
    error_message = "basedb tier must not create any exadb-d VM clusters."
  }
}
