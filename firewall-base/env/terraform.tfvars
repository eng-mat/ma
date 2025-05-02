default_project = "default-project"
default_region  = "us-central1"

firewall_rules = {
  "rule1" = {
    project_id = "default-project"
    network    = "default"
    rule_name  = "allow--ad1"
    priority   = 1000

    allow_rules = [
      { protocol = "tcp", ports = ["22", "80", "443"] },
      { protocol = "udp", ports = ["123"] }
    ]

    source_ranges      = ["10.10.10.0/27"]
    destination_ranges = ["10.10.1.0/24"]
 #   target_tags        = ["web-server"]
    description        = "Allow SSH, HTTP/S, and NTP"
  }

  "rule2" = {
    project_id = "default-project"
    network    = "host-vpc"
    rule_name  = "allow--ad2"
    priority   = 1010

    allow_rules = [
      { protocol = "tcp", ports = ["8080", "8443"] },
      { protocol = "icmp", ports = [] }
    ]

    source_ranges      = ["192.168.0.0/16"]
    destination_ranges = ["172.16.0.0/12"]
  #  target_tags        = ["custom-service"]
    description        = "Allow custom TCP and ICMP traffic"
  }

  "rule3" = {
    project_id = "network-prj1"
    network    = "firewall-test12"
    rule_name  = "allow--ad1"
    priority   = 1000

    allow_rules = [
      { protocol = "tcp", ports = ["22", "80", "443"] },
      { protocol = "udp", ports = ["123"] }
    ]

    source_ranges      = ["10.10.10.0/27"]
    destination_ranges = ["10.10.1.0/24"]
 #   target_tags        = ["web-server"]
    description        = "Allow SSH, HTTP/S, and NTP"
  }

  "rule4" = {
    project_id = "network-prj1"
    network    = "firewall-test1"
    rule_name  = "allow--ad2"
    priority   = 1010

    allow_rules = [
      { protocol = "tcp", ports = ["8080", "8443"] },
      { protocol = "icmp", ports = [] }
    ]

    source_ranges      = ["192.168.0.0/16"]
    destination_ranges = ["172.16.0.0/12"]
  #  target_tags        = ["custom-service"]
    description        = "Allow custom TCP and ICMP traffic"
  }


  "rule5" = {
    project_id = "network-prj1"
    network    = "network"
    rule_name  = "allow--ad3"
    priority   = 1010

    allow_rules = [
      { protocol = "tcp", ports = ["8080", "8443"] },
      { protocol = "icmp", ports = [] }
    ]

    source_ranges      = ["192.168.0.0/16"]
    destination_ranges = ["172.16.0.0/12"]
  #  target_tags        = ["custom-service"]
    description        = "Allow custom TCP and ICMP traffic"
  }

  "rule3" = {
    project_id = "firewall-test-458613"
    network    = "default"
    rule_name  = "allow--ad1"
    priority   = 1000

    allow_rules = [
      { protocol = "tcp", ports = ["22", "80", "443"] },
      { protocol = "udp", ports = ["123"] }
    ]

    source_ranges      = ["10.10.10.0/27"]
    destination_ranges = ["10.10.1.0/24"]
 #   target_tags        = ["web-server"]
    description        = "Allow SSH, HTTP/S, and NTP"
  }

  "rule4" = {
    project_id = "firewall-test-458613"
    network    = "test123"
    rule_name  = "allow--ad2"
    priority   = 1010

    allow_rules = [
      { protocol = "tcp", ports = ["8080", "8443"] },
      { protocol = "icmp", ports = [] }
    ]

    source_ranges      = ["192.168.0.0/16"]
    destination_ranges = ["172.16.0.0/12"]
  #  target_tags        = ["custom-service"]
    description        = "Allow custom TCP and ICMP traffic"
  }


}
