variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}
variable "state_bucket" { type = string }
variable "env" { type = string }
variable "secret_ids" { type = list(string) }
variable "accessor_sa_name" { type = string }
