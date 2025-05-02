# backend.tf
terraform {
  backend "gcs" {
    bucket = "bucket_name" # Replace with your GCS bucket name
    prefix = "terraform/firewall"
  }
}

provider "google" {
  project = "project_id"
  region  = "us-central1"
}