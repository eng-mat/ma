output "id" {
  description = "Reasoning Engine resource id - the agents pipeline deploys into this."
  value       = google_vertex_ai_reasoning_engine.this.id
}

output "name" {
  value = google_vertex_ai_reasoning_engine.this.name
}
