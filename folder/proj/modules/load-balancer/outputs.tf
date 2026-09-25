output "ip_address" {
  description = "Internal VIP for the frontend. Point the custom domain's private DNS record here."
  value       = google_compute_forwarding_rule.this.ip_address
}
