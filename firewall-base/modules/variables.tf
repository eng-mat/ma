variable "project_id" {
  type = string
}

variable "network" {
  type = string
}

variable "rule_name" {
  type = string
}

variable "priority" {
  type    = number
  default = 1000
}

variable "allow_rules" {
  type = list(object({
    protocol = string
    ports    = list(string)
  }))
}

variable "source_ranges" {
  type = list(string)
}

variable "destination_ranges" {
  type = list(string)
}

variable "target_tags" {
  type    = list(string)
  default = []
}

variable "description" {
  type    = string
  default = ""
}
