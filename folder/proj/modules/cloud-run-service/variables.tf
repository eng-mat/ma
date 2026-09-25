variable "project_id" {
  type = string
}

variable "name" {
  description = "Cloud Run service name."
  type        = string
}

variable "location" {
  type = string
}

variable "service_account_email" {
  description = "Runtime service account for the revision (created by the iam module in the stack)."
  type        = string
}

variable "container_image" {
  description = <<-EOT
    Bootstrap image Terraform sets on first create. After that the app pipeline owns
    the running image - see the ignore_changes on the container image below - so a
    plain "hello" placeholder is fine here until the team ships their first build.
  EOT
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "ingress" {
  description = "Ingress. Internal-only behind the internal load balancer by default."
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
}

variable "vpc_access" {
  description = "Serverless VPC Access egress. connector is the connector id; egress ALL_TRAFFIC routes everything through the VPC."
  type = object({
    connector = string
    egress    = optional(string, "PRIVATE_RANGES_ONLY")
  })
  default = null
}

variable "min_instance_count" {
  type    = number
  default = 0
}

variable "max_instance_count" {
  type    = number
  default = 10
}

variable "environment_variables" {
  description = "Plain (non-secret) environment variables."
  type        = map(string)
  default     = {}
}

variable "env_secret_vars" {
  description = "Environment variables sourced from Secret Manager (secret id + version)."
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default = {}
}

variable "startup_probe" {
  description = "Optional HTTP startup probe."
  type = object({
    path                  = optional(string, "/")
    port                  = optional(number, 8080)
    initial_delay_seconds = optional(number, 0)
    period_seconds        = optional(number, 10)
    timeout_seconds       = optional(number, 1)
    failure_threshold     = optional(number, 3)
  })
  default = null
}

variable "invoker_members" {
  description = "Members granted roles/run.invoker (e.g. the internal LB service agent, the scheduler SA)."
  type        = list(string)
  default     = []
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "labels" {
  type    = map(string)
  default = {}
}
