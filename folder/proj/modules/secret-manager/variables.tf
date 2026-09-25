variable "project_id" {
  description = "Project that owns the secrets."
  type        = string
}

variable "default_labels" {
  description = "Labels merged onto every secret."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = <<-EOT
    Secret CONTAINERS to create (never values - values are added out of band by an
    operator or a privileged pipeline). accessor_members are granted
    roles/secretmanager.secretAccessor, typically the runtime SA that reads the secret.
  EOT
  type = map(object({
    labels           = optional(map(string), {})
    accessor_members = optional(list(string), [])
  }))
  default = {}
}

variable "replica_locations" {
  description = "If set, use user-managed replication pinned to these locations. Empty = automatic replication."
  type        = list(string)
  default     = []
}

variable "kms_key_by_location" {
  description = "Optional CMEK key id per location for user-managed replication (location => crypto key id)."
  type        = map(string)
  default     = {}
}
