variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}
variable "state_bucket" { type = string }
variable "env" { type = string }
variable "name_prefix" { type = string }
variable "network" { type = string }
variable "subnetwork" { type = string }
variable "ssl_certificate_id" {
  type    = string
  default = null
}
variable "iap_members" {
  type    = list(string)
  default = []
}
