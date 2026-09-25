data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "${var.env}/iam"
  }
}

module "cloud_run" {
  source                = "../../../modules/cloud-run-service"
  project_id            = var.project_id
  name                  = var.name
  location              = var.region
  service_account_email = data.terraform_remote_state.iam.outputs.emails[var.name]
  ingress               = var.ingress
  deletion_protection   = var.env == "prod"
}
