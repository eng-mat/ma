terraform {
  backend "gcs" {
    bucket = "bucket-path"
    prefix = "terraform/firewall"
  }
}

provider "google" {
  project     = "project-id"
}
