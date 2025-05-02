resource "google_compute_firewall" "this" {
  name    = var.rule_name
  project = var.project_id
  network = var.network

  direction = "INGRESS"
  priority  = var.priority
  disabled  = false

  dynamic "allow" {
    for_each = var.allow_rules
    content {
      protocol = allow.value.protocol
      ports    = allow.value.ports
    }
  }

  source_ranges      = var.source_ranges
  destination_ranges = var.destination_ranges
 # target_tags        = var.target_tags
  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
  description        = var.description
}
