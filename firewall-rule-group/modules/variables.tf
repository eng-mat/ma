# variables.tf (modules)
variable "project_id" {
  type = string
  description = "The ID of the project in which to create firewall rules."
}

variable "network" {
  type = string
  description = "The name of the network to apply the firewall rules to."
}

variable "rule_name" {
  type = string
  description = "The name of the firewall rule."
}

variable "priority" {
  type = number
  description = "The priority of the firewall rule."
}

variable "allow_rules" {
  type = list(object({ protocol = string, ports = list(string) }))
  description = "List of allowed protocols and ports."
}

variable "source_ranges" {
  type = list(string)
  description = "List of source IP ranges."
}

variable "destination_ranges" {
  type = list(string)
  description = "List of destination IP ranges."
}

variable "description" {
  type = string
  description = "Description of the firewall rule."
}
