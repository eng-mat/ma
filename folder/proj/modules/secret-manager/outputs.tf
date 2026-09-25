output "secret_ids" {
  description = "Map of secret key => full resource id."
  value       = { for k, s in google_secret_manager_secret.this : k => s.id }
}

output "secret_names" {
  description = "Map of secret key => secret_id (short name)."
  value       = { for k, s in google_secret_manager_secret.this : k => s.secret_id }
}
