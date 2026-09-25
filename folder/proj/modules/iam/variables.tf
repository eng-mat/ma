variable "project_id" {
  description = "Project the service accounts live in."
  type        = string
}

variable "service_accounts" {
  description = <<-EOT
    Service accounts to create, keyed by a short name. project_roles are granted on
    project_id; extra_roles let you grant on another project (e.g. a data project we
    only read from) as "<project_id>=><role>" style entries.
  EOT
  type = map(object({
    display_name  = string
    description   = optional(string, "")
    project_roles = optional(list(string), [])
    # roles to grant on OTHER projects: { "some-data-project" = ["roles/bigquery.dataViewer"] }
    external_project_roles = optional(map(list(string)), {})
  }))
  default = {}
}

variable "project_iam_members" {
  description = "Additive role bindings on project_id for members created elsewhere (additive, never authoritative)."
  type = list(object({
    role   = string
    member = string
  }))
  default = []
}
