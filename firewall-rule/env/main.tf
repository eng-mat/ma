module "firewall_rules" {
  for_each = var.firewall_rules

  source = "./modules/firewall_rule"

  project_id         = each.value.project_id
  network            = each.value.network
  rule_name          = each.value.rule_name
  priority           = each.value.priority
  allow_rules        = each.value.allow_rules
  source_ranges      = each.value.source_ranges
  destination_ranges = each.value.destination_ranges
 # target_tags        = each.value.target_tags
  description        = each.value.description
}
