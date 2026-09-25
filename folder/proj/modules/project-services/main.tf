# Enable the APIs a stack needs. Idempotent and safe to re-run: if the platform
# team already enabled a service, Terraform adopts it rather than fighting it.
#
# disable_on_destroy stays false by default because these projects are shared and
# vended by the platform team - a `destroy` here should never rip an API out from
# under another workload in the same project.
resource "google_project_service" "this" {
  for_each = toset(var.services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = var.disable_on_destroy
}
