variable "project_id" {
  type = string
}

variable "location" {
  description = "Discovery Engine location (global, us, or eu)."
  type        = string
  default     = "us"
}

variable "data_store_id" {
  description = "Data store id (RAG grounding corpus for the agents)."
  type        = string
}

variable "display_name" {
  type = string
}

variable "industry_vertical" {
  type    = string
  default = "GENERIC"
}

variable "content_config" {
  type    = string
  default = "CONTENT_REQUIRED"
}

variable "create_search_engine" {
  description = "Also create a search engine (app) over the data store."
  type        = bool
  default     = true
}

variable "search_engine_id" {
  type    = string
  default = null
}
