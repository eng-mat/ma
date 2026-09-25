# INTERNAL (regional) Application Load Balancer fronting the frontend Cloud Run service.
# There is NO external exposure - load_balancing_scheme is INTERNAL_MANAGED and the VIP
# lives on an internal subnet. Access is further restricted by IAP to the Okta allow-group.
#
# Prerequisite: a proxy-only subnet (purpose REGIONAL_MANAGED_PROXY) must exist in this
# region and VPC (requested from the platform team). The custom domain resolves - via
# internal/private DNS - to this LB's internal VIP.

locals {
  use_https       = var.ssl_certificate_id != null
  forwarding_port = local.use_https ? "443" : "80"
}

resource "google_compute_region_network_endpoint_group" "neg" {
  project               = var.project_id
  name                  = "${var.name_prefix}-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.cloud_run_service_name
  }
}

resource "google_compute_region_backend_service" "this" {
  project               = var.project_id
  name                  = "${var.name_prefix}-bes"
  region                = var.region
  load_balancing_scheme = "INTERNAL_MANAGED"
  protocol              = "HTTPS"

  backend {
    group           = google_compute_region_network_endpoint_group.neg.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  dynamic "iap" {
    for_each = var.enable_iap ? [1] : []
    content {
      enabled = true
    }
  }
}

resource "google_compute_region_url_map" "this" {
  project         = var.project_id
  name            = "${var.name_prefix}-urlmap"
  region          = var.region
  default_service = google_compute_region_backend_service.this.id
}

resource "google_compute_region_target_https_proxy" "https" {
  count            = local.use_https ? 1 : 0
  project          = var.project_id
  name             = "${var.name_prefix}-https-proxy"
  region           = var.region
  url_map          = google_compute_region_url_map.this.id
  ssl_certificates = [var.ssl_certificate_id]
}

resource "google_compute_region_target_http_proxy" "http" {
  count   = local.use_https ? 0 : 1
  project = var.project_id
  name    = "${var.name_prefix}-http-proxy"
  region  = var.region
  url_map = google_compute_region_url_map.this.id
}

resource "google_compute_forwarding_rule" "this" {
  project               = var.project_id
  name                  = "${var.name_prefix}-fr"
  region                = var.region
  load_balancing_scheme = "INTERNAL_MANAGED"
  network               = var.network
  subnetwork            = var.subnetwork
  ip_address            = var.ip_address
  ip_protocol           = "TCP"
  port_range            = local.forwarding_port
  target                = local.use_https ? google_compute_region_target_https_proxy.https[0].id : google_compute_region_target_http_proxy.http[0].id
}

# Restrict access to the Okta allow-group through IAP.
resource "google_iap_web_region_backend_service_iam_member" "members" {
  for_each = var.enable_iap ? toset(var.iap_members) : []

  project                    = var.project_id
  region                     = var.region
  web_region_backend_service = google_compute_region_backend_service.this.name
  role                       = "roles/iap.httpsResourceAccessor"
  member                     = each.value
}
