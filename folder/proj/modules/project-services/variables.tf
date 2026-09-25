variable "project_id" {
  description = "Project in which to enable services. Vended by the platform team."
  type        = string
}

variable "services" {
  description = "APIs to enable (e.g. run.googleapis.com)."
  type        = list(string)
  default     = []
}

variable "disable_on_destroy" {
  description = "Whether to disable the API when the resource is destroyed. Keep false in shared projects."
  type        = bool
  default     = false
}
