default_project = "main-host-project"
default_region  = "us-central1"

firewall_rules = {
  "rule1" = {
    project_id = "host-project-1"
    network    = "vpc-1"
    rule_name  = "allow-web-and-ssh"
    priority   = 1000

    allow_rules = [
      { protocol = "tcp", ports = ["22", "80", "443"] },
      { protocol = "udp", ports = ["123"] }
    ]

    source_ranges      = ["0.0.0.0/0"]
    destination_ranges = ["10.10.1.0/24"]
 #   target_tags        = ["web-server"]
    description        = "Allow SSH, HTTP/S, and NTP"
  }

  "rule2" = {
    project_id = "host-project-2"
    network    = "vpc-x"
    rule_name  = "custom-firewall"
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
