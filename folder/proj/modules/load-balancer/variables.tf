variable "project_id" {
  type = string
}

variable "name_prefix" {
  description = "Prefix for the LB resources (e.g. cde-dev-frontend)."
  type        = string
}

variable "region" {
  type = string
}

variable "network" {
  description = "Self-link/id of the (Shared) VPC network. INTERNAL only."
  type        = string
}

variable "subnetwork" {
  description = "Self-link of the subnet used to allocate the internal VIP."
  type        = string
}

variable "cloud_run_service_name" {
  description = "The frontend Cloud Run service this internal LB fronts."
  type        = string
}

variable "ssl_certificate_id" {
  description = "Regional SSL certificate id (from the customer's internal CA / Certificate Manager). If set, the LB serves HTTPS on 443; otherwise HTTP on 80."
  type        = string
  default     = null
}

variable "ip_address" {
  description = "Optional static internal IP for the forwarding rule."
  type        = string
  default     = null
}

variable "enable_iap" {
  type    = bool
  default = true
}

variable "iap_members" {
  description = "Members granted access through IAP (the Okta allow-group), e.g. group:cde-app-users@company.com."
  type        = list(string)
  default     = []
}
