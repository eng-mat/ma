# terraform.tfvars (environment)

# Firewall rule definitions, grouped by purpose
firewall_rules = {
  # Rules applied to "domain" services
  domain = {
    "allow-domain-ssh-http" = {
      project_id         = "prj1"
      network            = "default"
      rule_name          = "domain-allow--ad2"
      priority           = 1000
      allow_rules        = [{ protocol = "tcp", ports = ["22", "80", "443"] }, { protocol = "udp", ports = ["123"] }]
      source_ranges      = ["10.10.10.0/27"]
      destination_ranges = ["10.10.1.0/24"]
      description        = "Allow SSH, HTTP/S, and NTP for domain services"
    },
    "allow-domain-ssh-http2" = {
      project_id         = "prj2"
      network            = "test123"
      rule_name          = "domain-allow--ad2"
      priority           = 1000
      allow_rules        = [{ protocol = "tcp", ports = ["22", "80", "443"] }, { protocol = "udp", ports = ["123"] }]
      source_ranges      = ["10.10.10.0/27"]
      destination_ranges = ["10.10.1.0/24"]
      description        = "Allow SSH, HTTP/S, and NTP for domain services"
    },
    "allow-domain-ssh-http25" = {
      project_id         = "prj2"
      network            = "test123"
      rule_name          = "domain-allow-aaa"
      priority           = 1000
      allow_rules        = [{ protocol = "tcp", ports = ["22", "80", "443"] }, { protocol = "udp", ports = ["123"] }]
      source_ranges      = ["10.10.10.0/27"]
      destination_ranges = ["10.10.1.0/24"]
      description        = "Allow SSH, HTTP/S, and NTP for domain services"
    }
    # Add more domain-related rules here
  }

  # Rules applied to GKE clusters
  gke = {
    "allow-gke-ingress" = {
      project_id         = "prj1"
      network            = "host-vpc"
      rule_name          = "allow--ad1"
      priority           = 1000
      allow_rules        = [{ protocol = "tcp", ports = ["80", "443", "8080"] }]
      source_ranges      = ["0.0.0.0/0"]
      destination_ranges = ["10.20.0.0/16"]
      description        = "Allow ingress traffic to GKE cluster"
    },
    "allow-gke-node-health" = {
      project_id         = "prj1"
      network            = "default"
      rule_name          = "allow--ad2"
      priority           = 1010
      allow_rules        = [{ protocol = "tcp", ports = ["10256"] }]
      source_ranges      = ["35.191.0.0/16", "130.211.0.0/22"]
      destination_ranges = ["10.20.0.0/16"]
      description        = "Allow GKE node health checks"
    }
    # Add more GKE-related rules here
  }

  # Rules applied to MongoDB instances
  mongodb = {
    "allow-mongodb-access" = {
      project_id         = "prj3"
      network            = "maex-global-store-vpc"
      rule_name          = "allow--ad10"
      priority           = 1000
      allow_rules        = [{ protocol = "tcp", ports = ["27017"] }]
      source_ranges      = ["10.30.0.0/24"]
      destination_ranges = ["10.40.0.0/24"]
      description        = "Allow access to MongoDB from application network"
    }
    # Add more MongoDB-related rules here
  }

  # Example of a new rule group
  app_servers = {
    "allow-app-server-http" = {
      project_id         = "prj1"
      network            = "default"
      rule_name          = "allow--ad194"
      priority           = 1000
      allow_rules        = [{ protocol = "tcp", ports = ["80", "443"] }]
      source_ranges      = ["192.168.1.0/24"]
      destination_ranges = ["10.50.0.0/24"]
      description        = "Allow HTTP/S traffic to app servers"
    }
  }

  # You can add more rule groups here (e.g., "database", etc.)
  # Following the same structure as above.
}
