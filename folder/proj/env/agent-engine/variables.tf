variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}
variable "state_bucket" { type = string }
variable "env" { type = string }
variable "display_name" { type = string }
variable "runtime_sa_name" { type = string }
