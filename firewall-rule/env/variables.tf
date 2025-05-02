variable "default_project" {
  type = string
}

variable "default_region" {
  type = string
}

variable "firewall_rules" {
  type = map(object({
    project_id         = string
    network            = string
    rule_name          = string
    priority           = number
    allow_rules        = list(object({
      protocol = string
      ports    = list(string)
    }))
    source_ranges      = list(string)
    destination_ranges = list(string)
    target_tags        = list(string)
    description        = string
  }))
}
