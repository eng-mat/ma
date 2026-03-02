# DNS-AgentEngine-OneTime: One-Time Private DNS Setup for Vertex AI Agent Engine PSC Interfaces

**Status:** Draft (One-Time Prerequisite)  
**Date:** March 02, 2026  
**Author:** (GCP Engineering Team)  
**Audience:** Networking Team / DNS Admins (Host Project Owners)  
**Related ADR:** ADR-AgentEngine-001

## Purpose

This document describes the **one-time** private DNS configuration needed (or recommended) to provide friendly hostname resolution for **Vertex AI Agent Engine** PSC interfaces deployed via self-service.

Agent Engine uses **Private Service Connect Interface (PSC-I)**. Each deployment gets an auto-provisioned internal IP from the PSC-I subnet in the host VPC.  

- The Vertex AI SDK and agent runtime handle resolution automatically when `dns_peering_configs` are set at deployment time.  
- For better developer experience (avoid hardcoding IPs), friendly DNS names are recommended (e.g. agent-myapp-us-central1.mycompany.internal).  

DNS setup is **optional** and **not** part of the Terraform module or per-deployment automation. App teams handle it post-deployment using our existing self-service DNS tool.

## Recommended DNS Pattern

Use a **private Cloud DNS managed zone** in the host project(s) (non-prod/prod).

- Zone DNS name (suffix): mycompany.internal. (or your established private domain)  
- Record type: A (direct mapping to PSC interface IP)  
- Visibility: Private — attached to the host VPC network(s)  
- Location: Regional or global (global preferred for multi-region simplicity)

Example friendly name:  
agent-<team>-<workload>-<region>.mycompany.internal → A record to <PSC interface IP>

## Leveraging Existing Self-Service DNS

We already have a self-service portal for DNS records (originally for GKE Istio and internal load balancer IPs).  

Use the **same self-service** for Agent Engine PSC interfaces:  

- Record Type: A (direct IP mapping)  
- Inputs from app team (after deployment via console):  
  - Custom hostname: e.g. agent-myapp-us-central1.mycompany.internal  
  - Target: PSC interface IP (shown in console post-deployment)  
  - TTL: 300–3600 seconds (standard)  
  - Zone: Existing private zone (e.g. mycompany.internal)  
- No special approvals required beyond current process  
- Self-service link: [Insert actual internal portal URL here, e.g. https://console.mycompany.com/dns-selfservice]

This keeps consistency — app teams already know the flow from GKE/ILB usage.

## One-Time Setup Steps (Networking Team)

If a suitable private zone does not already exist or needs extension:

- Create Private Managed Zone (if needed):  
  ```bash
  gcloud dns managed-zones create agentengine-private-zone \
    --dns-name="mycompany.internal." \
    --description="Private DNS for internal services including Agent Engine PSC" \
    --visibility=private \
    --networks="https://www.googleapis.com/compute/v1/projects/HOST_PROJECT/global/networks/HOST_VPC" \
    --project=HOST_PROJECT

- Attach to all relevant host VPCs (non-prod/prod)
- Use regional zone if per-region isolation is preferred
- Enable Cloud DNS API in host project (if not already enabled)
- Verify Zone Attachment: Confirm resolution works from service projects via Shared VPC (DNS inherits from host network)
- Communicate to App Teams:
  - Update internal wiki/Confluence: "For Agent Engine PSC friendly names, use the standard DNS self-service tool with A records pointing to the PSC interface IP shown in the deployment console."
  - No wildcard records needed — per-hostname A records are sufficient and handled by self-service


**No Changes Needed for Automation/Console Team**

- DNS is post-deployment and optional
- Console returns the raw PSC interface IP (and can suggest friendly name format)
- No Terraform DNS resources in the Agent Engine module
- If app teams skip DNS → they use IP directly or rely on automatic DNS peering (still fully functional)

**References**

- Cloud DNS Private Zones: https://cloud.google.com/dns/docs/zones#creating-a-private-zone
- Adding Records to Private Zones: https://cloud.google.com/dns/docs/records
- PSC Interface DNS Guidance: https://cloud.google.com/vertex-ai/docs/general/psc-interfaces
- Vertex AI PSC-I Setup (mentions DNS peering): https://cloud.google.com/vertex-ai/docs/general/vpc-psc-i-setup

This one-time setup enables consistent, developer-friendly DNS without adding complexity to the core Agent Engine automation.
