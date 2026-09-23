variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}
variable "location_id" { type = string }
variable "delete_protection" { type = bool }
variable "daily_backup_retention" { type = string }
