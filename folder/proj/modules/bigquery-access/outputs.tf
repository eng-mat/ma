output "owned_dataset_ids" {
  description = "Map of dataset key => full dataset id."
  value       = { for k, d in google_bigquery_dataset.owned : k => d.id }
}
