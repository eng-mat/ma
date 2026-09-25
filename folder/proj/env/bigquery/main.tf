data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "${var.env}/iam"
  }
}

locals {
  backend_member = data.terraform_remote_state.iam.outputs.members[var.backend_sa_name]
  grants = concat(
    [for ds in var.source_datasets : {
      dataset_project = ds.project, dataset_id = ds.dataset_id,
      role            = "roles/bigquery.dataViewer", member = local.backend_member
    }],
    [{
      dataset_project = var.project_id, dataset_id = "cde_working",
      role            = "roles/bigquery.dataEditor", member = local.backend_member
    }],
  )
}

module "bigquery" {
  source         = "../../../modules/bigquery-access"
  project_id     = var.project_id
  owned_datasets = { cde_working = { location = var.bq_location, description = "CDE working set + agent memory" } }
  dataset_iam    = local.grants
}
