# Vertex AI Search: a data store (grounding corpus) and, optionally, a search engine
# over it. The agents use this for RAG - grounded narratives and contextual Q&A. The
# ML team owns what gets ingested; we just provision the store + app.
resource "google_discovery_engine_data_store" "this" {
  project           = var.project_id
  location          = var.location
  data_store_id     = var.data_store_id
  display_name      = var.display_name
  industry_vertical = var.industry_vertical
  content_config    = var.content_config
  solution_types    = ["SOLUTION_TYPE_SEARCH"]
}

resource "google_discovery_engine_search_engine" "this" {
  count = var.create_search_engine ? 1 : 0

  project        = var.project_id
  location       = google_discovery_engine_data_store.this.location
  engine_id      = coalesce(var.search_engine_id, "${var.data_store_id}-engine")
  collection_id  = "default_collection"
  display_name   = var.display_name
  data_store_ids = [google_discovery_engine_data_store.this.data_store_id]

  search_engine_config {
    search_tier = "SEARCH_TIER_ENTERPRISE"
  }
}
