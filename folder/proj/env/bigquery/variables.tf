variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}
variable "state_bucket" { type = string }
variable "env" { type = string }
variable "bq_location" { type = string }
variable "backend_sa_name" { type = string }
variable "source_datasets" {
  type = list(object({
    project    = string
    dataset_id = string
  }))
  default = []
}
