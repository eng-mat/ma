# Vertex AI Agent Engine (Reasoning Engine). Terraform creates the engine with a tiny
# placeholder app so the resource can exist; the agents repo then deploys the real
# orchestrator + L1 specialists via agents-cli/SDK. ignore_changes below means those
# deploys are never fought or reverted by a terraform apply.

data "archive_file" "placeholder" {
  type        = "zip"
  source_dir  = "${path.module}/placeholder"
  output_path = "${path.module}/.build/placeholder.zip"
}

resource "google_vertex_ai_reasoning_engine" "this" {
  display_name    = var.display_name
  description     = var.description
  region          = var.region
  project         = var.project_id
  deletion_policy = var.deletion_policy
  labels          = var.labels

  timeouts {
    create = "60m"
    update = "60m"
    delete = "30m"
  }

  spec {
    service_account = var.runtime_service_account_email

    source_code_spec {
      inline_source {
        source_archive = filebase64(data.archive_file.placeholder.output_path)
      }

      python_spec {
        entrypoint_module = "app.agent"
        entrypoint_object = "agent"
        requirements_file = "requirements.txt"
        version           = "3.12"
      }
    }

    deployment_spec {
      min_instances = var.min_instances
      max_instances = var.max_instances

      dynamic "psc_interface_config" {
        for_each = var.network_attachment_id == null ? [] : [var.network_attachment_id]
        content {
          network_attachment = psc_interface_config.value
        }
      }
    }
  }

  # After create, the agents pipeline owns the app + runtime spec. Terraform must not
  # redeploy or revert it - so we ignore the source and the tunable deployment fields.
  lifecycle {
    ignore_changes = [
      spec[0].source_code_spec,
      spec[0].deployment_spec[0].min_instances,
      spec[0].deployment_spec[0].max_instances,
    ]
  }
}
