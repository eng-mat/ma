output "data_store_id" {
  value = google_discovery_engine_data_store.this.data_store_id
}

output "engine_id" {
  value       = try(google_discovery_engine_search_engine.this[0].engine_id, null)
  description = "Search engine id, or null when create_search_engine is false."
}
