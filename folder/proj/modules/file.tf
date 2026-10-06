resource "google_vertex_ai_reasoning_engine" "agent" {
  project      = var.project_id
  region       = var.region
  display_name = var.agent_engine_display_name
  description  = "CDE agent. Shell owned by infra-repo; code deployed by the agentic repo pipeline."

  labels = {
    managed-by = "terraform"
    owner      = "infra"
    app        = "cde-agent"
  }

  spec {
    deployment_spec {
      # Private egress: RFC 1918 traffic goes into our VPC via this attachment.
      # Google APIs (Gemini, Vertex AI Search) keep using Google's network.
      psc_interface_config {
        network_attachment = google_compute_network_attachment.agent.id

        # Resolve *.cde.internal from our private zone (DNS peering only).
        dns_peering_configs {
          domain         = var.internal_domain
          target_project = var.project_id
          target_network = google_compute_network.vpc.name
        }
      }
    }
  }

  # PREVENT makes Terraform refuse to delete or replace this engine — it holds
  # the app team's deployed agent and its sessions. Switch to FORCE in
  # terraform.tfvars only when you deliberately want to tear it down.
  deletion_policy = var.agent_engine_deletion_policy

  lifecycle {
    ignore_changes = [spec]
  }

  # The service agent must already be able to patch the attachment and peer
  # DNS when the engine is created.
  depends_on = [
    google_project_service.enabled,
    google_project_iam_member.vertex_psc_attachment,
    google_project_iam_member.vertex_dns_peer,
    google_dns_managed_zone.internal,
  ]
}
