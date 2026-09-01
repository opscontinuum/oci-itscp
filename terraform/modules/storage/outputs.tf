output "ashburn_file_system_id" {
  value = try(oci_file_storage_file_system.ashburn[0].id, null)
}

output "phoenix_file_system_id" {
  value = try(oci_file_storage_file_system.phoenix[0].id, null)
}

output "fss_replication_id" {
  value = try(oci_file_storage_replication.ashburn_to_phoenix[0].id, null)
}

output "ashburn_bucket_names" {
  value = { for k, b in oci_objectstorage_bucket.ashburn : k => b.name }
}

output "phoenix_bucket_names" {
  value = { for k, b in oci_objectstorage_bucket.phoenix : k => b.name }
}

# `bucket_id` (NOT `id` — oci_objectstorage_bucket has no `id` attribute;
# `bucket_id` is the Oracle-assigned OCID) — this is what an FSDR
# OBJECT_STORAGE_BUCKET member's member_id expects.
output "ashburn_bucket_ids" {
  value = { for k, b in oci_objectstorage_bucket.ashburn : k => b.bucket_id }
}

output "phoenix_bucket_ids" {
  value = { for k, b in oci_objectstorage_bucket.phoenix : k => b.bucket_id }
}

output "bucket_replication_policy_ids" {
  value = { for k, p in oci_objectstorage_replication_policy.ashburn_to_phoenix : k => p.id }
}

output "fsdr_log_bucket_ashburn_name" {
  value = try(oci_objectstorage_bucket.fsdr_logs_ashburn[0].name, null)
}

output "fsdr_log_bucket_phoenix_name" {
  value = try(oci_objectstorage_bucket.fsdr_logs_phoenix[0].name, null)
}

output "fsdr_log_bucket_storage_tiers" {
  description = "Standard tier, no replication, one per DR Protection Group (RB-05 Phase 5)."
  value = {
    ashburn = try(oci_objectstorage_bucket.fsdr_logs_ashburn[0].storage_tier, null)
    phoenix = try(oci_objectstorage_bucket.fsdr_logs_phoenix[0].storage_tier, null)
  }
}

output "interchange_bucket_count" {
  value = length(local.buckets)
}

output "replication_policy_count" {
  description = "Count of oci_objectstorage_replication_policy resources — must equal interchange_bucket_count exactly, never interchange_bucket_count + 2, which would mean an FSDR log bucket picked up a replication policy by mistake."
  value       = length(oci_objectstorage_replication_policy.ashburn_to_phoenix)
}
