data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "${var.env}/iam"
  }
}

module "agent_engine" {
  source                        = "../../../modules/agent-engine"
  project_id                    = var.project_id
  region                        = var.region
  display_name                  = var.display_name
  runtime_service_account_email = data.terraform_remote_state.iam.outputs.emails[var.runtime_sa_name]
}
