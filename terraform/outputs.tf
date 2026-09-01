####################################################################
# outputs.tf — apply-lock status, module pass-throughs, and the BOM
# for the OCI Cost Estimator (docs/05-cost-and-teardown.md — "No
# prices appear in this document"; likewise no prices here).
####################################################################

output "apply_lock_status" {
  description = "Human-readable posture: LOCKED (default, safe, zero resources) or UNLOCKED."
  value       = local.apply_unlocked ? "UNLOCKED — resources will plan/apply" : "LOCKED — every resource plans to count/for_each = 0 (default, safe posture)"
}

output "required_spend_acknowledgement_phrase" {
  description = "Exact string spend_acknowledgement must equal, given the current spend_acknowledgement_duration. Empty duration means the phrase can never match — set spend_acknowledgement_duration first."
  value       = local.required_spend_phrase
}

output "bom" {
  description = <<-EOT
    Tier-C cheap-variant Bill of Materials for the OCI Cost Estimator
    (https://www.oracle.com/cloud/costestimator.html). Line items only,
    no prices — model your own rates per docs/05-cost-and-teardown.md.
    This BOM assumes database_tier = "basedb"; the exadb-d tier (this
    plan's actual documented design, docs/01 A2) is priced separately
    with the Exadata Database Service on Dedicated Infrastructure
    estimator category, using exadata_shape/exadata_compute_count/
    exadata_storage_count from modules/database.
  EOT
  value = [
    "2x Base Database VM DB system (1 node, ${var.database_tier == "basedb" ? "2" : "n/a — exadb-d selected"} OCPU, 256 GB) — 1 in ${var.primary_region}, 1 standby in ${var.dr_region}",
    "5x VM.Standard.E5.Flex 1 OCPU / 8 GB — Ashburn app tier (IAD-EBSWEB01/02, IAD-EBSCM01/02, IAD-BI01)",
    "5x VM.Standard.E5.Flex 1 OCPU / 8 GB — Phoenix app tier twins (PHX-EBSWEB01/02, PHX-EBSCM01/02, PHX-BI01)",
    "~600 GB block volume (5x 120 GB) + Volume Group Replication, Ashburn -> Phoenix",
    "2x Object Storage bucket (ebs-interfaces, ebs-archive) + Replication Policy, Ashburn -> Phoenix",
    "2x Object Storage bucket, Standard tier, no replication — one per DR Protection Group, plan-execution logs only",
    "2x File Storage file system + Mount Target + File System Replication, Ashburn -> Phoenix",
    "2x Flexible Load Balancer (public, WAF-attached), one per region",
    "1x DR Protection Group pair (Ashburn <-> Phoenix) + 4 DR Plans (Switchover, Failover, Start Drill, Stop Drill)",
    "1x Autonomous Recovery Service protected database (primary region only)",
    "1x OCI Monitoring notification topic + 6 alarms",
    "1x OCI Resource Scheduler WARM-posture stop schedule (4 of 5 Phoenix app nodes — BI excluded)",
  ]
}

output "network" {
  value = {
    ashburn_vcn_id = module.network.ashburn_vcn_id
    phoenix_vcn_id = module.network.phoenix_vcn_id
  }
}

output "compute" {
  value = {
    ashburn_instance_ids              = module.compute.ashburn_instance_ids
    phoenix_instance_ids              = module.compute.phoenix_instance_ids
    ashburn_instance_states           = module.compute.ashburn_instance_states
    phoenix_instance_states           = module.compute.phoenix_instance_states
    ashburn_run_command_plugin_states = module.compute.ashburn_run_command_plugin_states
    phoenix_run_command_plugin_states = module.compute.phoenix_run_command_plugin_states
    always_on_phoenix_instance_ids    = module.compute.always_on_phoenix_instance_ids
    stoppable_phoenix_instance_ids    = module.compute.stoppable_phoenix_instance_ids
  }
}

output "database" {
  value = {
    tier                   = module.database.database_tier
    ashburn_vm_cluster_id  = module.database.ashburn_vm_cluster_id
    phoenix_vm_cluster_id  = module.database.phoenix_vm_cluster_id
    ashburn_db_system_id   = module.database.ashburn_db_system_id
    basedb_license_model   = module.database.basedb_license_model
    ashburn_cpu_core_count = module.database.ashburn_cpu_core_count
    phoenix_cpu_core_count = module.database.phoenix_cpu_core_count
  }
}

output "fsdr" {
  value = {
    ashburn_drpg_id = module.fsdr.ashburn_drpg_id
    phoenix_drpg_id = module.fsdr.phoenix_drpg_id
    plan_ids        = module.fsdr.plan_ids
  }
}

output "recovery" {
  value = {
    protected_database_id  = module.recovery.protected_database_id
    retention_lock_enabled = module.recovery.retention_lock_enabled
  }
}

output "storage" {
  value = {
    ashburn_bucket_names     = module.storage.ashburn_bucket_names
    phoenix_bucket_names     = module.storage.phoenix_bucket_names
    interchange_bucket_count = module.storage.interchange_bucket_count
    replication_policy_count = module.storage.replication_policy_count
    fsdr_log_bucket_ashburn  = module.storage.fsdr_log_bucket_ashburn_name
    fsdr_log_bucket_phoenix  = module.storage.fsdr_log_bucket_phoenix_name
    fsdr_log_bucket_tiers    = module.storage.fsdr_log_bucket_storage_tiers
  }
}

output "lb" {
  value = {
    ashburn_lb_id = module.lb.ashburn_lb_id
    phoenix_lb_id = module.lb.phoenix_lb_id
  }
}

output "monitoring_notification_topic_id" {
  value = module.monitoring.notification_topic_id
}

output "scheduler_warm_posture_stop_schedule_id" {
  value = module.scheduler.warm_posture_stop_schedule_id
}
