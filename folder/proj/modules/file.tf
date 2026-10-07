# Staging bucket, managed in this same configuration.
resource "google_storage_bucket" "staging" {
  project                     = var.project_id
  name                        = var.staging_bucket
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }
}

# JFrog -> GCS: the pipeline downloads the archive from JFrog to
# var.agent_archive_path, and Terraform uploads it here. GCS holds the deployed
# version; JFrog keeps the full version history.
resource "google_storage_bucket_object" "agent_source" {
  bucket = google_storage_bucket.staging.name
  name   = "agent-engine/${var.agent_version}/agent-engine-${var.agent_version}.tar.gz"
  source = var.agent_archive_path
}

# The bucket already exists — look it up instead of creating it.
data "google_storage_bucket" "staging" {
  name = var.staging_bucket
}

# The agent source archive the pipeline copied from JFrog into GCS. Terraform
# reads it here and sends it to Agent Engine inline (the API takes the archive
# itself, not a GCS path). The plan fails if the object isn't there.
data "google_storage_bucket_object_content" "agent_source" {
  bucket = data.google_storage_bucket.staging.name
  name   = var.agent_source_object
}



resource "google_vertex_ai_reasoning_engine" "agent" {
  project      = var.project_id
  region       = var.region
  display_name = var.agent_engine_display_name
  description  = "CDE agent deployed from a source archive (JFrog -> GCS)."

  labels = {
    managed-by    = "terraform"
    app           = "cde-agent"
    agent-version = replace(var.agent_version, ".", "-") # label values can't contain dots
  }

  spec {
    agent_framework = "google-adk"
    service_account = var.runtime_service_account

    # Lets SDK clients discover the agent's methods (create_session,
    # stream_query, ...). Export it once from an SDK-deployed engine.
    class_methods = file("${path.module}/class_methods.json")

    # ONE archive: the same .tar.gz Terraform just copied to GCS. The API takes
    # the archive bytes (base64), not a GCS path. Agent Engine builds it.
    source_code_spec {
      inline_source {
        source_archive = filebase64(var.agent_archive_path)
      }

      python_spec {
        entrypoint_module = var.entrypoint_module
        entrypoint_object = var.entrypoint_object
        requirements_file = var.requirements_file
        version           = var.python_version
      }
    }

    deployment_spec {
      dynamic "env" {
        for_each = var.agent_env
        content {
          name  = env.key
          value = env.value
        }
      }

      # Optional private egress into the VPC (to reach internal services).
      dynamic "psc_interface_config" {
        for_each = var.network_attachment_id == null ? [] : [1]
        content {
          network_attachment = var.network_attachment_id

          dynamic "dns_peering_configs" {
            for_each = var.dns_peering_configs
            content {
              domain         = dns_peering_configs.value.domain
              target_project = dns_peering_configs.value.target_project
              target_network = dns_peering_configs.value.target_network
            }
          }
        }
      }
    }
  }

  deletion_policy = var.agent_engine_deletion_policy

  # Record the artifact in GCS before deploying it.
  depends_on = [google_storage_bucket_object.agent_source]
}






variable "project_id" {
  description = "Project that hosts the Agent Engine."
  type        = string
}

variable "region" {
  description = "Agent Engine region (must match the network attachment's region if PSC-I is used)."
  type        = string
}

variable "staging_bucket" {
  description = "Name of the staging bucket created by this configuration."
  type        = string
}

variable "agent_version" {
  description = "Agent release version (from JFrog), e.g. 0.1.2. Bump to release."
  type        = string
}

variable "agent_archive_path" {
  description = "Local path where the pipeline downloaded the agent .tar.gz from JFrog."
  type        = string
}

variable "python_version" {
  description = "Python version Agent Engine builds the source with (e.g. 3.12)."
  type        = string
}

variable "entrypoint_module" {
  description = "Python module (inside the archive) that defines the agent, e.g. cde_agent.agent."
  type        = string
}

variable "entrypoint_object" {
  description = "Object in entrypoint_module that is the agent, e.g. root_agent."
  type        = string
}

variable "requirements_file" {
  description = "Requirements file path relative to the archive root."
  type        = string
}

variable "runtime_service_account" {
  description = "Service account the agent runs as (email)."
  type        = string
}

variable "agent_engine_display_name" {
  type = string
}

variable "agent_engine_deletion_policy" {
  description = "PREVENT blocks Terraform from deleting/replacing the engine; FORCE deletes it even with child sessions."
  type        = string

  validation {
    condition     = contains(["PREVENT", "DELETE", "FORCE", "ABANDON"], var.agent_engine_deletion_policy)
    error_message = "Must be one of PREVENT, DELETE, FORCE, ABANDON."
  }
}

variable "agent_env" {
  description = "Environment variables for the agent runtime."
  type        = map(string)
}

variable "network_attachment_id" {
  description = "PSC network attachment id for private egress, or null for none. Fixed at engine creation."
  type        = string
}

variable "dns_peering_configs" {
  description = "Private DNS zones the agent may resolve (used only with PSC-I). Fixed at engine creation."
  type = list(object({
    domain         = string # zone suffix with trailing dot, e.g. "dev.gcp.example.com."
    target_project = string # project hosting the private zone
    target_network = string # VPC network NAME the zone is bound to
  }))
}










project_id     = "firewall-test-458613"
region         = "us-central1"
staging_bucket = "firewall-test-458613-cde-agent-staging" # existing bucket

# The single archive the pipeline copied JFrog -> GCS. Must be .tar.gz.
# Bump this path to release a new version.
agent_source_object = "agent-engine/0.1.2/agent-engine-0.1.2-a1b2c3d.tar.gz"

# What's inside the archive (paths relative to its root)
entrypoint_module = "cde_agent.agent"
entrypoint_object = "root_agent"
requirements_file = "requirements.txt"
python_version    = "3.12"

runtime_service_account = "cde-agent-runtime@firewall-test-458613.iam.gserviceaccount.com"

agent_engine_display_name    = "cde-agent"
agent_engine_deletion_policy = "DELETE"

agent_env = {
  GCP_PROJECT     = "firewall-test-458613"
  SEARCH_LOCATION = "global"
  DATA_STORE_ID   = "cde-grounding-store"
}

# Private egress (PSC-I). Leave null / [] for none. Fixed at engine creation.
network_attachment_id = null
dns_peering_configs   = []





project_id     = "firewall-test-458613"
region         = "us-central1"
staging_bucket = "firewall-test-458613-cde-agent-staging"

# Release: bump agent_version; the pipeline downloads that version from JFrog
# to agent_archive_path before running terraform. Must be a .tar.gz.
agent_version      = "0.1.2"
agent_archive_path = "dist/agent-engine.tar.gz"

# What's inside the archive (paths relative to its root)
entrypoint_module = "cde_agent.agent"
entrypoint_object = "root_agent"
requirements_file = "requirements.txt"
python_version    = "3.12"

runtime_service_account = "cde-agent-runtime@firewall-test-458613.iam.gserviceaccount.com"

agent_engine_display_name    = "cde-agent"
agent_engine_deletion_policy = "DELETE"

agent_env = {
  GCP_PROJECT     = "firewall-test-458613"
  SEARCH_LOCATION = "global"
  DATA_STORE_ID   = "cde-grounding-store"
}

# Private egress (PSC-I). Leave null / [] for none. Fixed at engine creation.
network_attachment_id = null
dns_peering_configs   = []




