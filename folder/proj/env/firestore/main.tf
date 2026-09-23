module "firestore" {
  source                 = "../../../modules/firestore"
  project_id             = var.project_id
  location_id            = var.location_id
  delete_protection      = var.delete_protection
  daily_backup_retention = var.daily_backup_retention
}
