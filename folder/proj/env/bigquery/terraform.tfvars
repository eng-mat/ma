project_id      = "REPLACE-cde-dev"
region          = "us-central1"
state_bucket    = "REPLACE-cde-tfstate"
env             = "dev"
bq_location     = "US"
backend_sa_name = "cde-dev-backend"

source_datasets = [
  # { project = "REPLACE-edc-src", dataset_id = "EDC_SRC_DATA" },
]
