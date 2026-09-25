variable "project_id" {
  description = "Project that owns the datasets we create (e.g. the CDE working/snapshot datasets)."
  type        = string
}

variable "default_labels" {
  type    = map(string)
  default = {}
}

variable "owned_datasets" {
  description = <<-EOT
    Datasets this platform owns and writes: the CDE working dataset (status + package
    JSON) and the frozen snapshot/audit dataset. The agent (via the CDE Backend MCP's
    SA) is granted dataEditor on these through dataset_iam below.
  EOT
  type = map(object({
    location    = string
    description = optional(string, "")
    kms_key     = optional(string)
    labels      = optional(map(string), {})
  }))
  default = {}
}

variable "dataset_iam" {
  description = <<-EOT
    Dataset-level, additive IAM. Use this to grant READ on the existing vended source
    datasets (dataViewer) and READ/WRITE on our owned datasets (dataEditor). Additive
    only - never authoritative - so we don't disturb the source datasets' owners.
  EOT
  type = list(object({
    dataset_project = string
    dataset_id      = string
    role            = string
    member          = string
  }))
  default = []
}
