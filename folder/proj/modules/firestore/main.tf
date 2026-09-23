# Firestore (Native). Feature-rich by design: CMEK, PITR, delete protection, concurrency
# mode, and daily/weekly backup schedules are all available. Environments pass only the
# few knobs they need; everything else stays on the secure defaults above.

resource "google_firestore_database" "this" {
  project     = var.project_id
  name        = var.database_name
  location_id = var.location_id
  type        = var.type

  concurrency_mode            = var.concurrency_mode
  app_engine_integration_mode = var.app_engine_integration_mode

  point_in_time_recovery_enablement = var.point_in_time_recovery ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"
  delete_protection_state           = var.delete_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  deletion_policy                   = var.deletion_policy

  dynamic "cmek_config" {
    for_each = var.cmek_kms_key == null ? [] : [var.cmek_kms_key]
    content {
      kms_key_name = cmek_config.value
    }
  }
}

resource "google_firestore_backup_schedule" "daily" {
  count = var.daily_backup_retention == null ? 0 : 1

  project   = var.project_id
  database  = google_firestore_database.this.name
  retention = var.daily_backup_retention

  daily_recurrence {}
}

resource "google_firestore_backup_schedule" "weekly" {
  count = var.weekly_backup == null ? 0 : 1

  project   = var.project_id
  database  = google_firestore_database.this.name
  retention = var.weekly_backup.retention

  weekly_recurrence {
    day = var.weekly_backup.day
  }
}
