output "name" {
  description = "Cloud Run service name."
  value       = google_cloud_run_v2_service.this.name
}

output "uri" {
  description = "Default service URI (internal)."
  value       = google_cloud_run_v2_service.this.uri
}

output "id" {
  value = google_cloud_run_v2_service.this.id
}
