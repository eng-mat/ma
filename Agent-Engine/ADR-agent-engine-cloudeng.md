# Proxy-Setup-AgentEngine-OneTime: One-Time Setup of Zscaler Egress Proxy VM/MIG for Agent Engine

**Status:** Draft (One-Time Prerequisite)  
**Date:** March 02, 2026  
**Author:** (GCP Engineering Team)  
**Audience:** Cloud Engineering Team (Host Project Owners)  
**Related ADR:** ADR-AgentEngine-001

## Purpose

This document provides the exact steps to deploy a secure, HTTPS-only forward proxy (on port 3128) in each host project (non-prod/prod) per region.  

The proxy enforces:  
- HTTPS traffic only (CONNECT method to port 443)  
- Rejects plain HTTP  
- All outbound traffic routed through existing Zscaler via network tag  

Agent Engine will send non-RFC1918 traffic to this proxy IP:3128 → proxy → Zscaler path.

## Prerequisites (before starting)

- Host project selected (non-prod or prod)  
- Region selected (where PSC-I subnet exists or will exist)  
- Existing Zscaler network tag name known (e.g. `zscaler-egress`)  
- Existing VM creation automation or template available (Container-Optimized OS preferred)  
- Separate subnet for proxy VMs/MIG recommended (not the PSC-I subnet)  
- Firewall rules will be created in the host VPC

## Step-by-Step Setup (chronological order)

### Step 1 – Create dedicated proxy subnet (if not already present)

```bash
gcloud compute networks subnets create proxy-agentengine-us-central1 \
  --project=HOST_PROJECT_ID \
  --network=projects/HOST_PROJECT_ID/global/networks/HOST_VPC_NAME \
  --region=us-central1 \
  --range=10.201.0.0/24 \
  --purpose=PRIVATE
Use a small /24 or /23 per region — proxy VMs need very few IPs.
Step 2 – Deploy proxy VM or Managed Instance Group (MIG)
Use your existing VM deployment automation / template. Key requirements:

Machine type: e2-micro or e2-small (very low traffic expected)
Image: Container-Optimized OS (cos-stable) or hardened image approved by security
Network tag: your existing Zscaler tag (e.g. zscaler-egress)
Network: host VPC
Subnet: the proxy subnet created above
Service account: minimal (no default scopes needed beyond logging if desired)
Startup metadata or container: install & configure tinyproxy (recommended for simplicity)

Preferred: Use Managed Instance Group for HA
Create instance template first (adapt to your automation):
Bashgcloud compute instance-templates create agentengine-proxy-template-us-central1 \
  --project=HOST_PROJECT_ID \
  --machine-type=e2-small \
  --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=proxy-agentengine-us-central1 \
  --tags=zscaler-egress \
  --image-family=cos-stable \
  --image-project=cos-cloud \
  --metadata-from-file=startup-script=startup-proxy.sh
Example minimal startup-proxy.sh (install tinyproxy, allow only HTTPS CONNECT):
Bash#!/bin/bash
apt-get update -y
apt-get install -y tinyproxy

cat > /etc/tinyproxy/tinyproxy.conf << 'EOF'
Port 3128
Listen 0.0.0.0
Allow 10.200.0.0/20          # ← replace with your PSC-I subnet CIDR(s)
ConnectPort 443
DisableViaHeader Yes
FilterDefaultDeny Yes
EOF

systemctl enable tinyproxy
systemctl restart tinyproxy
Then create MIG (2–3 instances across zones):
Bashgcloud compute instance-groups managed create agentengine-proxy-mig-us-central1 \
  --project=HOST_PROJECT_ID \
  --template=agentengine-proxy-template-us-central1 \
  --size=2 \
  --zone=us-central1-a \
  --zones=us-central1-a,us-central1-b,us-central1-c
Step 3 – Create firewall rules (Host VPC)
Allow PSC-I subnet(s) to reach proxy on port 3128 only:
Bash# Allow PSC-I → proxy (repeat for each PSC-I subnet if multiple)
gcloud compute firewall-rules create allow-psci-to-proxy-3128 \
  --project=HOST_PROJECT_ID \
  --direction=INGRESS \
  --priority=1000 \
  --network=HOST_VPC_NAME \
  --action=ALLOW \
  --rules=tcp:3128 \
  --source-ranges=10.200.0.0/20 \          # ← your PSC-I subnet CIDR
  --target-tags=proxy-agentengine          # optional: add tag to proxy VMs if desired

# Allow proxy outbound to Zscaler (your existing rules should already cover this via tag)
# If not, ensure egress rule exists for tag zscaler-egress to 0.0.0.0/0 on tcp:80,443
Allow proxy health checks (if using MIG):
Bashgcloud compute firewall-rules create allow-healthcheck-to-proxy \
  --project=HOST_PROJECT_ID \
  --direction=INGRESS \
  --priority=1000 \
  --network=HOST_VPC_NAME \
  --action=ALLOW \
  --rules=tcp:3128 \
  --source-ranges=35.191.0.0/16,130.211.0.0/22 \  # GCP health check ranges
  --target-tags=proxy-agentengine
Step 4 – Create MIG health check (for auto-healing)
Bashgcloud compute health-checks create tcp proxy-tcp-3128 \
  --port=3128 \
  --proxy-header=NONE \
  --check-interval=5s \
  --timeout=5s \
  --healthy-threshold=2 \
  --unhealthy-threshold=2

gcloud compute instance-groups managed update agentengine-proxy-mig-us-central1 \
  --health-check=proxy-tcp-3128 \
  --initial-delay=60s
Step 5 – Test the proxy
From a test VM in the same VPC (PSC-I subnet range):
Bash# Should succeed (HTTPS)
curl -x http://<proxy-ip>:3128 https://www.google.com

# Should fail (plain HTTP blocked)
curl -x http://<proxy-ip>:3128 http://example.com
Check Zscaler logs / Cloud NAT metrics to confirm egress path.
Step 6 – Record & Share

Proxy IPs (or internal DNS name if you create one)
Port: 3128
Allowed source: PSC-I subnet CIDR(s)
Hand over to Automation team for self-service parameterization

Repeat for each region and each host project (non-prod/prod).
This setup ensures strict HTTPS-only egress through Zscaler while remaining simple and maintainable.
