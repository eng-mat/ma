# variables.tf (environment)
variable "firewall_rules" {
  type = map(map(object({
    project_id         = string
    network            = string
    rule_name          = string
    priority           = number
    allow_rules        = list(object({ protocol = string, ports = list(string) }))
    source_ranges      = list(string)
    destination_ranges = list(string)
    description        = string
  })))
  description = "Map of firewall rule groups."
}
