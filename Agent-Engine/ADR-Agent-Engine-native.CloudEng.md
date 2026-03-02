# Proxy-Setup-AgentEngine-OneTime: One-Time Setup of Secure Web Proxy (SWP) for Agent Engine Egress

**Status:** Draft (One-Time Prerequisite)  
**Date:** March 02, 2026  
**Author:** Matthew (GCP Engineering Team)  
**Audience:** Cloud Engineering Team (Host Project Owners)  
**Related ADR:** ADR-AgentEngine-001

## Purpose

Deploy a managed **Secure Web Proxy (SWP)** in explicit forward-proxy mode per region in each host project (non-prod/prod).  

The SWP:
- Listens on port 3128 (standard explicit proxy port)
- Allows **HTTPS only** (CONNECT method to destination port 443)
- Rejects plain HTTP
- Forwards all traffic upstream to your existing Zscaler (no SWP inspection, filtering, decryption, or logging)
- Ensures Agent Engine internet egress goes through Zscaler (via your existing Cloud NAT + Zscaler network tag path)

This eliminates VM patching, open-source software approval, and operational overhead.

## Prerequisites

- Host project (non-prod or prod) and region selected
- Existing Zscaler egress path (network tag + Cloud NAT + Zscaler Cloud Connector)
- Zscaler proxy details known (IP:port or hostname:port where SWP should forward CONNECT requests)
- PSC-I subnet already exists (or will be created) in the same region
- APIs enabled in host project: compute.googleapis.com, networkservices.googleapis.com

## Step-by-Step Setup (chronological gcloud commands)

### Step 1 – Create dedicated proxy-only subnet (required for SWP)

This subnet hosts Google-managed proxy instances (purpose = REGIONAL_MANAGED_PROXY).

```bash
gcloud compute networks subnets create swp-proxy-only-us-central1 \
  --project=HOST_PROJECT_ID \
  --network=projects/HOST_PROJECT_ID/global/networks/HOST_VPC_NAME \
  --region=us-central1 \
  --range=10.202.0.0/24 \
  --purpose=REGIONAL_MANAGED_PROXY

Use /24 or larger if you expect high concurrent connections (rare for Agent Engine)
Do not use this subnet for anything else

Step 2 – Create the Secure Web Proxy gateway (explicit mode)
Bashgcloud network-security secure-web-proxy create agentengine-swp-us-central1 \
  --project=HOST_PROJECT_ID \
  --location=us-central1 \
  --organization=ORG_ID \
  --proxy-only-subnet=swp-proxy-only-us-central1
Step 3 – Configure explicit HTTPS proxy policy (allow only CONNECT to 443)
Bashgcloud network-security secure-web-proxy proxy-policy create agentengine-https-only-policy \
  --project=HOST_PROJECT_ID \
  --location=us-central1 \
  --secure-web-proxy=agentengine-swp-us-central1 \
  --rule-action=ALLOW \
  --rule-match-http-method=CONNECT \
  --rule-match-destination-port=443 \
  --rule-match-protocol=https \
  --priority=1000
Add a default deny rule for everything else (including plain HTTP):
Bashgcloud network-security secure-web-proxy proxy-policy create agentengine-deny-all \
  --project=HOST_PROJECT_ID \
  --location=us-central1 \
  --secure-web-proxy=agentengine-swp-us-central1 \
  --rule-action=DENY \
  --priority=2000
Step 4 – Set upstream proxy forwarding to Zscaler
Bashgcloud network-services gateway create agentengine-swp-gateway-us-central1 \
  --project=HOST_PROJECT_ID \
  --location=us-central1 \
  --secure-web-proxy=agentengine-swp-us-central1 \
  --upstream-proxy=your-zscaler-proxy.example.com:8080 \
  --upstream-proxy-type=HTTP_CONNECT

Replace your-zscaler-proxy.example.com:8080 with your actual Zscaler explicit proxy endpoint (IP:port or hostname:port)
If Zscaler uses authentication, add credentials via --upstream-proxy-username / --upstream-proxy-password flags (or use secrets manager if preferred)

Step 5 – Create firewall rules (Host VPC)
Allow PSC-I subnet(s) to reach SWP on port 3128:
Bashgcloud compute firewall-rules create allow-psci-to-swp-3128 \
  --project=HOST_PROJECT_ID \
  --direction=INGRESS \
  --priority=1000 \
  --network=HOST_VPC_NAME \
  --action=ALLOW \
  --rules=tcp:3128 \
  --source-ranges=10.200.0.0/20 \          # ← your PSC-I subnet CIDR (repeat for additional subnets)
  --destination-ranges=10.202.0.0/24       # ← proxy-only subnet range
Allow SWP health checks (Google-managed):
Bashgcloud compute firewall-rules create allow-healthcheck-to-swp \
  --project=HOST_PROJECT_ID \
  --direction=INGRESS \
  --priority=1000 \
  --network=HOST_VPC_NAME \
  --action=ALLOW \
  --rules=tcp:3128 \
  --source-ranges=35.191.0.0/16,130.211.0.0/22 \  # GCP health check ranges
  --destination-ranges=10.202.0.0/24
Step 6 – Verify & Test

Get SWP internal IP (or use DNS name if you set one up):Bashgcloud network-services gateway describe agentengine-swp-gateway-us-central1 \
  --project=HOST_PROJECT_ID \
  --location=us-central1
Test from a VM in the VPC (PSC-I subnet range):Bash# Should succeed (HTTPS)
curl -x http://<swp-ip>:3128 https://www.google.com

# Should fail (HTTP blocked)
curl -x http://<swp-ip>:3128 http://example.com
Confirm in Zscaler logs that traffic arrives from the SWP-forwarded path

Step 7 – Record & Handover

SWP internal IP (or regional DNS name if created)
Port: 3128
Allowed sources: PSC-I subnet CIDR(s)
Share with Automation team for self-service parameterization

Repeat for each region and each host project (non-prod/prod).
This setup provides managed, HTTPS-only egress through Zscaler with no double inspection and minimal cost.
