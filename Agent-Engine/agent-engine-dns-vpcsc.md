# DNS-AgentEngine-OneTime: One-Time Private DNS Setup for Vertex AI Agent Engine PSC Interfaces and Regional SWP Hostnames

**Status:** Draft (One-Time Prerequisite)  
**Date:** March 02, 2026  
**Author:** Matthew (GCP Engineering Team)  
**Audience:** Networking Team / DNS Admins (Host Project Owners)  
**Related ADR:** ADR-AgentEngine-001

## Purpose

This document outlines the **one-time** private DNS configuration required (or recommended) to enable friendly and reliable hostname resolution for **Vertex AI Agent Engine** PSC interfaces and the regional Secure Web Proxy (SWP) hostnames created via self-service.

Agent Engine deployments use **Private Service Connect Interface (PSC-I)** and receive an auto-provisioned internal IP from the PSC-I subnet in the host VPC.

Important notes:
- Not all Agent Engine instances require internet egress. Many communicate only within the internal network (GKE, Cloud Run, internal APIs, on-prem via Interconnect, etc.).
- Internal traffic remains fully private and direct via PSC-I — **no proxy/SWP involvement**.
- Only outbound/internet-bound traffic (when needed) is routed to the regional Secure Web Proxy (SWP) via explicit configuration in the agent runtime (e.g., HTTPS_PROXY environment variable).
- The Vertex AI SDK and agent runtime automatically resolve internal domains when `dns_peering_configs` are configured at deployment time.
- The regional SWP hostname (e.g. agentengine-swp-us-central1.mycompany.internal) is centrally managed by Cloud Engineering and does **not** require per-deployment records — app teams use it only when outbound access is configured.
- Friendly DNS names improve developer experience by avoiding hardcoded IPs (e.g. agent-myapp-us-central1.mycompany.internal for PSC IP or internal services).

DNS configuration is **optional** and managed by app teams post-deployment using the existing self-service DNS portal.

## Recommended DNS Pattern

Use a **private Cloud DNS managed zone** in the host project(s) (non-prod/prod).

- Zone DNS name (suffix): mycompany.internal. (or your established private domain)
- Record type: A (direct mapping to PSC interface IP or internal service IPs)
- Visibility: Private — attached to the host VPC network(s)
- Location: Regional or global (global preferred for multi-region simplicity)

Example friendly name (for internal resolution):  
agent-<team>-<workload>-<region>.mycompany.internal → A record to <PSC interface IP>

## Leveraging Existing Self-Service DNS

We already have a self-service portal for creating DNS records (originally built for GKE Istio and internal load balancer IPs).

App teams use the **same self-service portal** for Agent Engine PSC interfaces and internal services:
- Record Type: A (direct IP mapping)
- Inputs from app team (after deployment via console):
  - Custom hostname: e.g. agent-myapp-us-central1.mycompany.internal
  - Target: PSC interface IP (shown in console post-deployment) or internal service IP
  - TTL: 300–3600 seconds (standard)
  - Zone: Existing private zone (e.g. mycompany.internal)
- For outbound/internet access, app teams use the pre-filled regional SWP hostname provided by the console (no additional DNS record needed from them — central A record already exists in the host zone)
- No special approvals required beyond current process
- Self-service link: [Insert actual internal portal URL here, e.g. https://console.mycompany.com/dns-selfservice]

This maintains consistency — app teams already know the workflow from GKE/ILB usage.  
Each team controls DNS peering and resolution for their own Agent Engine via `dns_peering_configs`, ensuring internal-only agents never route through the proxy.

## One-Time Setup Steps (Networking Team)

If a suitable private zone does not already exist or needs extension:
- Create Private Managed Zone (if needed):
  ```bash
  gcloud dns managed-zones create agentengine-private-zone \
    --dns-name="mycompany.internal." \
    --description="Private DNS for internal services including Agent Engine PSC and regional SWP hostnames" \
    --visibility=private \
    --networks="https://www.googleapis.com/compute/v1/projects/HOST_PROJECT/global/networks/HOST_VPC" \
    --project=HOST_PROJECT

Attach to all relevant host VPCs (non-prod/prod)
Use regional zone if per-region isolation is preferred
Enable Cloud DNS API in host project (if not already enabled)
Verify Zone Attachment: Confirm resolution works from service projects via Shared VPC (DNS inherits from host network)
Communicate to App Teams:
Update internal wiki/Confluence:
"For Agent Engine PSC friendly names or internal service resolution, use the standard DNS self-service tool with A records pointing to the PSC interface IP or internal endpoints shown in the deployment console. Internal-only agents do not require proxy/SWP routing. For outbound agents, use the regional SWP hostname automatically pre-filled in the console when outbound is selected."
No wildcard records needed — per-hostname A records are sufficient and handled by self-service


Integration Guidance for Automation & Console Team
While DNS configuration is fully optional and post-deployment, the console and automation can make the experience smoother for app teams:

Display the PSC interface IP clearly after successful deployment (with a copy button)
Show a suggestion box: "To create a friendly name (e.g. agent-myapp-us-central1.mycompany.internal), use the DNS self-service portal: [link]"
If outbound is selected, pre-fill the regional SWP hostname (e.g. agentengine-swp-${region}.mycompany.internal:3128) in the HTTPS_PROXY field
Include a tooltip: "Configure dns_peering_configs in your agent deployment to resolve internal domains. Internal traffic bypasses SWP."
Optionally pre-populate example dns_peering_configs in the Terraform module documentation (keep it optional — app teams decide which zones to peer)

These small enhancements reduce friction without adding DNS as a required step or moving it into automation.
References

Cloud DNS Private Zones: https://cloud.google.com/dns/docs/zones#creating-a-private-zone
Adding Records to Private Zones: https://cloud.google.com/dns/docs/records
PSC Interface DNS Guidance: https://cloud.google.com/vertex-ai/docs/general/psc-interfaces
Vertex AI PSC-I Setup (mentions DNS peering): https://cloud.google.com/vertex-ai/docs/general/vpc-psc-i-setup

This one-time setup enables consistent, developer-friendly DNS while giving app teams full control over peering and ensuring internal-only Agent Engine instances remain fully private (no proxy/SWP involvement).
