variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "display_name" {
  description = "Agent Engine display name (e.g. cde-dev-orchestrator)."
  type        = string
}

variable "description" {
  type    = string
  default = "CDE Agent Engine (bootstrapped by Terraform, deployed by the agents pipeline)."
}

variable "runtime_service_account_email" {
  description = "Runtime SA the engine runs as (created by the iam module)."
  type        = string
}

variable "network_attachment_id" {
  description = "Optional PSC network attachment id for private egress from the engine."
  type        = string
  default     = null
}

variable "min_instances" {
  type    = number
  default = 1
}

variable "max_instances" {
  type    = number
  default = 2
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "deletion_policy" {
  type    = string
  default = "DELETE"
}
