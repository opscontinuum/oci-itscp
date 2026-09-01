output "notification_topic_id" {
  value = try(oci_ons_notification_topic.dr[0].id, null)
}

output "alarm_ids" {
  value = {
    dg_transport_lag_phx   = try(oci_monitoring_alarm.dg_transport_lag_phx[0].id, null)
    dg_apply_lag_phx       = try(oci_monitoring_alarm.dg_apply_lag_phx[0].id, null)
    dg_apply_lag_iad2      = try(oci_monitoring_alarm.dg_apply_lag_iad2[0].id, null)
    volume_replica_age     = try(oci_monitoring_alarm.volume_replica_age[0].id, null)
    fss_recovery_point_age = try(oci_monitoring_alarm.fss_recovery_point_age[0].id, null)
    phoenix_ocpu_floor     = try(oci_monitoring_alarm.phoenix_ocpu_floor[0].id, null)
  }
}
