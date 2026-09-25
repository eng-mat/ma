output "enabled_services" {
  description = "The set of services this module manages."
  value       = sort([for s in google_project_service.this : s.service])
}
