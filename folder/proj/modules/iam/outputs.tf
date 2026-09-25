output "emails" {
  description = "Map of SA key => email."
  value       = { for k, sa in google_service_account.this : k => sa.email }
}

output "members" {
  description = "Map of SA key => IAM member string (serviceAccount:...)."
  value       = { for k, sa in google_service_account.this : k => sa.member }
}
