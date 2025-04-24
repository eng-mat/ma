#variables.tf
variable "service_project" {}
variable "host_project" {}
variable "region" {}
variable "zone" {}
variable "host_vpc" {}
variable "subnet_name" {}
variable "workbench_name" {}
variable "cmek_key" {}
variable "machine_type" {}
variable "owner_email" {}
variable "cloud_eng_group" {}
variable "customer_group_email" {}


#terraform.tfvars
service_project        = "my-service-project"
host_project           = "my-host-project"
region                 = "us-central1"
zone                   = "us-central1-a"
host_vpc               = "host-vpc"
subnet_name            = "workbench-subnet"
workbench_name         = "notebook-v7"
cmek_key               = "projects/my-project/locations/us-central1/keyRings/my-keyring/cryptoKeys/my-key"
machine_type           = "e2-standard-4"
owner_email            = "owner@example.com"
cloud_eng_group        = "cloud-eng@example.com"
customer_group_email   = "customer-group@example.com"


#main.tf
provider "google" {
  project = var.service_project
  region  = var.region
}

provider "google-beta" {
  project = var.service_project
  region  = var.region
}

# Service Account
resource "google_service_account" "vertexai_sa" {
  account_id   = "vertexai"
  display_name = "Vertex AI Workbench Service Account"
  project      = var.service_project
}

# Subnet IAM binding for service account
resource "google_compute_subnetwork_iam_member" "sa_network_access" {
  project    = var.host_project
  region     = var.region
  subnetwork = var.subnet_name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${google_service_account.vertexai_sa.email}"
}

# Subnet IAM binding for cloud engineers group
resource "google_compute_subnetwork_iam_member" "cloud_eng_access" {
  project    = var.host_project
  region     = var.region
  subnetwork = var.subnet_name
  role       = "roles/compute.networkUser"
  member     = "group:${var.cloud_eng_group}"
}

# Subnet IAM binding for customer group
resource "google_compute_subnetwork_iam_member" "customer_group_access" {
  project    = var.host_project
  region     = var.region
  subnetwork = var.subnet_name
  role       = "roles/compute.networkUser"
  member     = "group:${var.customer_group_email}"
}

# Vertex AI Workbench Instance
resource "google_notebooks_instance" "vertex_ai_workbench" {
  provider       = google-beta
  name           = var.workbench_name
  location       = var.zone
  project        = var.service_project

  vm_image {
    project = "deeplearning-platform-release"
    family  = "common-cpu-notebooks"
  }

  machine_type   = var.machine_type
  boot_disk_type = "PD_STANDARD"
  boot_disk_size_gb = 150
  data_disk_size_gb = 100

  subnet = "projects/${var.host_project}/regions/${var.region}/subnetworks/${var.subnet_name}"
  network = "projects/${var.host_project}/global/networks/${var.host_vpc}"

  service_account = google_service_account.vertexai_sa.email

  no_public_ip             = true
  no_proxy_access          = false
  no_realtime_access       = true

  kms_key = var.cmek_key

  instance_owners = [var.owner_email]

  upgrade_history {
    schedule = "WEEKLY:SATURDAY:21:00"
  }

  shielded_instance_config {
    enable_secure_boot          = false
    enable_integrity_monitoring = true
    enable_vtpm                 = true
  }

  metadata = {
    jupyter_notebook_version = "JUPYTER_4_PREVIEW"
  }
}
