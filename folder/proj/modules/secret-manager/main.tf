resource "google_secret_manager_secret" "this" {
  for_each = var.secrets

  project   = var.project_id
  secret_id = each.key
  labels    = merge(var.default_labels, each.value.labels)

  dynamic "replication" {
    for_each = length(var.replica_locations) == 0 ? [1] : []
    content {
      auto {}
    }
  }

  dynamic "replication" {
    for_each = length(var.replica_locations) > 0 ? [1] : []
    content {
      user_managed {
        dynamic "replicas" {
          for_each = var.replica_locations
          content {
            location = replicas.value

            dynamic "customer_managed_encryption" {
              for_each = contains(keys(var.kms_key_by_location), replicas.value) ? [1] : []
              content {
                kms_key_name = var.kms_key_by_location[replicas.value]
              }
            }
          }
        }
      }
    }
  }
}

# Grant read access to the runtime service accounts that consume each secret.
locals {
  accessor_bindings = merge([
    for secret_key, cfg in var.secrets : {
      for member in cfg.accessor_members :
      "${secret_key}:${member}" => {
        secret = secret_key
        member = member
      }
    }
  ]...)
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = local.accessor_bindings

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
