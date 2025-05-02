# main.tf (modules)
resource "google_compute_firewall" "firewall_rules" {
  project     = var.project_id
  name        = var.rule_name
  network     = var.network
  priority    = var.priority
  description = var.description

  dynamic "allow" {
    for_each = var.allow_rules
    content {
      protocol = allow.value.protocol
      ports    = allow.value.ports
    }
  }

  source_ranges      = var.source_ranges
  destination_ranges = var.destination_ranges
}
