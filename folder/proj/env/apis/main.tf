module "apis" {
  source     = "../../../modules/project-services"
  project_id = var.project_id
  services   = var.services
}
