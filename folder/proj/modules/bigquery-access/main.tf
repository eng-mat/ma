# We do NOT recreate the enterprise source datasets - they already exist and are vended.
# This module (a) creates the few datasets the platform genuinely owns (CDE working set,
# frozen snapshots) and (b) grants additive, least-privilege access to source datasets.

resource "google_bigquery_dataset" "owned" {
  for_each = var.owned_datasets

  project       = var.project_id
  dataset_id    = each.key
  location      = each.value.location
  friendly_name = each.key
  description   = each.value.description
  labels        = merge(var.default_labels, each.value.labels)

  dynamic "default_encryption_configuration" {
    for_each = each.value.kms_key == null ? [] : [each.value.kms_key]
    content {
      kms_key_name = default_encryption_configuration.value
    }
  }
}

# Additive dataset-level grants: dataViewer on source datasets, dataEditor on owned ones.
resource "google_bigquery_dataset_iam_member" "grants" {
  for_each = {
    for b in var.dataset_iam :
    "${b.dataset_project}:${b.dataset_id}:${b.role}:${b.member}" => b
  }

  project    = each.value.dataset_project
  dataset_id = each.value.dataset_id
  role       = each.value.role
  member     = each.value.member
}
