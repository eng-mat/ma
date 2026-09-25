variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}
variable "services" { type = list(string) }
