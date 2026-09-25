# Service accounts and their role bindings. We only ever use additive bindings
# (google_project_iam_member), never authoritative ones, so we never clobber
# grants made by the platform team or another stack in a shared project.

resource "google_service_account" "this" {
  for_each = var.service_accounts

  project      = var.project_id
  account_id   = each.key
  display_name = each.value.display_name
  description  = each.value.description
}

# Roles on the SA's own project.
locals {
  own_project_bindings = merge([
    for sa_key, sa in var.service_accounts : {
      for role in sa.project_roles :
      "${sa_key}:${role}" => {
        role   = role
        member = google_service_account.this[sa_key].member
      }
    }
  ]...)

  # Roles on other projects (e.g. read access to a vended data project).
  external_bindings = merge([
    for sa_key, sa in var.service_accounts : merge([
      for proj, roles in sa.external_project_roles : {
        for role in roles :
        "${sa_key}:${proj}:${role}" => {
          project = proj
          role    = role
          member  = google_service_account.this[sa_key].member
        }
      }
    ]...)
  ]...)
}

resource "google_project_iam_member" "own" {
  for_each = local.own_project_bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

resource "google_project_iam_member" "external" {
  for_each = local.external_bindings

  project = each.value.project
  role    = each.value.role
  member  = each.value.member
}

resource "google_project_iam_member" "extra" {
  for_each = {
    for b in var.project_iam_members : "${b.role}:${b.member}" => b
  }

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}
