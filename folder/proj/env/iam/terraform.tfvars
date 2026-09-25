project_id = "REPLACE-cde-dev"
region     = "us-central1"

service_accounts = {
  "cde-dev-frontend"      = { display_name = "Frontend run", project_roles = ["roles/secretmanager.secretAccessor"] }
  "cde-dev-backend"       = { display_name = "Backend run", project_roles = ["roles/secretmanager.secretAccessor", "roles/datastore.user", "roles/bigquery.dataEditor", "roles/bigquery.jobUser"] }
  "cde-dev-agent-runtime" = { display_name = "Agent Engine runtime", project_roles = ["roles/aiplatform.user", "roles/secretmanager.secretAccessor", "roles/logging.logWriter", "roles/discoveryengine.editor"] }
}
