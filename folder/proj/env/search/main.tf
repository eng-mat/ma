module "search" {
  source        = "../../../modules/vertex-ai-search"
  project_id    = var.project_id
  location      = var.location
  data_store_id = var.data_store_id
  display_name  = var.display_name
}
