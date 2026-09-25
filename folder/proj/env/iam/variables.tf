variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}
variable "service_accounts" {
  type = map(object({
    display_name  = string
    project_roles = optional(list(string), [])
  }))
}
