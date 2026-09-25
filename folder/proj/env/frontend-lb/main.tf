data "terraform_remote_state" "frontend" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "${var.env}/frontend"
  }
}

module "lb" {
  source                 = "../../../modules/load-balancer"
  project_id             = var.project_id
  name_prefix            = var.name_prefix
  region                 = var.region
  network                = var.network
  subnetwork             = var.subnetwork
  cloud_run_service_name = data.terraform_remote_state.frontend.outputs.service_name
  ssl_certificate_id     = var.ssl_certificate_id
  iap_members            = var.iap_members
}
