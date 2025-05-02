# outputs.tf (modules)
output "firewall_rule_name" {
  value = google_compute_firewall.firewall_rules.name
  description = "The name of the created firewall rule."
}
