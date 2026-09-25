data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "${var.env}/iam"
  }
}

module "secrets" {
  source     = "../../../modules/secret-manager"
  project_id = var.project_id
  secrets = {
    for id in var.secret_ids : id => {
      accessor_members = [data.terraform_remote_state.iam.outputs.members[var.accessor_sa_name]]
    }
  }
}
