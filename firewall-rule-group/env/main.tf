# main.tf (environment)
module "firewall" {
  source = "../modules"
  for_each = merge([
    for group_name, rules in var.firewall_rules : {
      for rule_name, rule in rules : "${group_name}-${rule_name}" => rule
    }
  ]...)

  project_id         = each.value.project_id
  network            = each.value.network
  rule_name          = each.value.rule_name
  priority           = each.value.priority
  allow_rules        = each.value.allow_rules
  source_ranges      = each.value.source_ranges
  destination_ranges = each.value.destination_ranges
  description        = each.value.description
}
