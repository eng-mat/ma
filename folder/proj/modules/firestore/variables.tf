# The module exposes the full surface; environments activate only what they need.

variable "project_id" {
  type = string
}

variable "location_id" {
  description = "Firestore location (e.g. nam5 or us-central1)."
  type        = string
}

variable "database_name" {
  description = "Database id. Firestore's default is \"(default)\"."
  type        = string
  default     = "(default)"
}

variable "type" {
  description = "FIRESTORE_NATIVE or DATASTORE_MODE."
  type        = string
  default     = "FIRESTORE_NATIVE"
}

variable "concurrency_mode" {
  description = "OPTIMISTIC, PESSIMISTIC, or OPTIMISTIC_WITH_ENTITY_GROUPS."
  type        = string
  default     = "OPTIMISTIC"
}

variable "app_engine_integration_mode" {
  description = "ENABLED or DISABLED."
  type        = string
  default     = "DISABLED"
}

variable "point_in_time_recovery" {
  description = "Enable PITR (continuous backup, 7-day window)."
  type        = bool
  default     = true
}

variable "delete_protection" {
  description = "Block deletion of the database."
  type        = bool
  default     = true
}

variable "deletion_policy" {
  description = "DELETE or ABANDON on `terraform destroy`."
  type        = string
  default     = "ABANDON"
}

variable "cmek_kms_key" {
  description = "Optional CMEK key (full resource id) to encrypt the database at rest."
  type        = string
  default     = null
}

variable "daily_backup_retention" {
  description = "If set (duration, e.g. \"604800s\" = 7d), create a daily backup schedule. Null disables."
  type        = string
  default     = null
}

variable "weekly_backup" {
  description = "Optional weekly backup schedule."
  type = object({
    retention = string # e.g. "8467200s"
    day       = string # MONDAY..SUNDAY
  })
  default = null
}
