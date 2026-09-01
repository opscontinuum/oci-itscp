# Tier-C "author only, never apply" posture — default state.
# No credentials required: the oci provider is fully mocked. The root
# module declares three oci provider configurations (default + aliases
# ashburn/phoenix, providers.tf) — each needs its own mock_provider block,
# matched by alias, or Terraform still tries to build a real client for the
# un-mocked aliases and fails with "did not find a proper configuration for
# tenancy".
mock_provider "oci" {}

mock_provider "oci" {
  alias = "ashburn"
}

mock_provider "oci" {
  alias = "phoenix"
}

run "locked_by_default_zero_resources" {
  command = plan

  # unlock_apply defaults to false; every other variable keeps its default.

  assert {
    condition     = local.apply_unlocked == false
    error_message = "apply_unlocked must be false by default."
  }

  assert {
    condition     = output.apply_lock_status == "LOCKED — every resource plans to count/for_each = 0 (default, safe posture)"
    error_message = "apply_lock_status output did not report LOCKED."
  }

  # network
  assert {
    condition     = length(module.network.ashburn_app_subnet_ids) == 0 && length(module.network.phoenix_app_subnet_ids) == 0
    error_message = "network module must create zero subnets when locked."
  }
  assert {
    condition     = module.network.ashburn_vcn_id == null && module.network.phoenix_vcn_id == null
    error_message = "network module must create zero VCNs when locked."
  }

  # compute
  assert {
    condition     = length(module.compute.ashburn_instance_ids) == 0 && length(module.compute.phoenix_instance_ids) == 0
    error_message = "compute module must create zero instances when locked."
  }

  # storage
  assert {
    condition     = length(module.storage.ashburn_bucket_names) == 0 && module.storage.ashburn_file_system_id == null
    error_message = "storage module must create zero buckets/file systems when locked."
  }
  assert {
    condition     = module.storage.fsdr_log_bucket_ashburn_name == null && module.storage.fsdr_log_bucket_phoenix_name == null
    error_message = "storage module must create zero FSDR log buckets when locked."
  }

  # lb
  assert {
    condition     = module.lb.ashburn_lb_id == null && module.lb.phoenix_lb_id == null
    error_message = "lb module must create zero load balancers when locked."
  }

  # database (default database_tier = exadb-d)
  assert {
    condition     = module.database.ashburn_vm_cluster_id == null && module.database.phoenix_vm_cluster_id == null
    error_message = "database module must create zero VM clusters when locked."
  }
  assert {
    condition     = module.database.ashburn_db_system_id == null
    error_message = "database module must create zero db systems when locked."
  }

  # recovery
  assert {
    condition     = module.recovery.protected_database_id == null
    error_message = "recovery module must create zero protected databases when locked."
  }

  # fsdr
  assert {
    condition     = module.fsdr.ashburn_drpg_id == null && module.fsdr.phoenix_drpg_id == null
    error_message = "fsdr module must create zero DR Protection Groups when locked."
  }
  assert {
    condition     = alltrue([for k, v in module.fsdr.plan_ids : v == null])
    error_message = "fsdr module must create zero DR plans when locked."
  }

  # monitoring
  assert {
    condition     = module.monitoring.notification_topic_id == null
    error_message = "monitoring module must create zero notification topics when locked."
  }
  assert {
    condition     = alltrue([for k, v in module.monitoring.alarm_ids : v == null])
    error_message = "monitoring module must create zero alarms when locked."
  }

  # scheduler
  assert {
    condition     = module.scheduler.warm_posture_stop_schedule_id == null
    error_message = "scheduler module must create zero schedules when locked."
  }
}

run "unlock_apply_true_without_acknowledgement_still_locked" {
  command = plan

  variables {
    unlock_apply = true
    # spend_acknowledgement / spend_acknowledgement_duration left unset —
    # this must NOT unlock anything; the apply_lock_guard precondition
    # below is what turns this into a loud failure. This run only proves
    # the resource-count side of the lock still holds up to the point the
    # precondition fires.
  }

  expect_failures = [
    terraform_data.apply_lock_guard,
    check.apply_lock_posture,
  ]
}
