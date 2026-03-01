# DNS-VectorSearch-OneTime: One-Time Private DNS Setup for Vertex AI Vector Search PSC Endpoints

**Status:** Draft (One-Time Prerequisite)  
**Date:** March 01, 2026  
**Author:** Matthew (GCP Engineering Team)  
**Audience:** Networking Team / DNS Admins (Host Project Owners)  
**Related ADR:** ADR-VectorSearch-001

## Purpose

This document outlines the **one-time** private DNS configuration required (or recommended) to enable friendly hostname resolution for **private Vertex AI Vector Search index endpoints** deployed via our self-service offering.

Vector Search endpoints use **Private Service Connect (PSC) in automated mode** (via pre-created Service Connection Policies). Each endpoint gets an auto-provisioned regional internal IP (from the PSC subnet in the host VPC).

- The Vertex AI SDK can connect directly using the raw IP or via `psc_network` param (auto-resolution in code).
- For better usability (avoid hardcoding IPs in app code), we recommend **friendly DNS names** (e.g., `vs-team-workload-us-central1.mycompany.internal` → points to the PSC IP).

This DNS setup is **optional** and **not** part of the Terraform module or per-deployment automation. App teams handle it themselves **after** deployment using our existing self-service DNS tool.

## Why Private DNS?

- PSC endpoints resolve via internal IPs only (no public DNS).
- Raw IPs are hard to manage in code/configs.
- Friendly names improve developer experience and reduce errors.
- Aligns with our existing patterns (GKE Istio, ILB IPs).

## Recommended DNS Pattern

Use a **private Cloud DNS managed zone** in the host project(s) (non-prod/prod).

- **Zone DNS name** (suffix): `mycompany.internal.` (or your enterprise private domain, e.g., `internal.mycompany.com.` if already set up).
- **Record type**: **A** (maps hostname directly to the PSC internal IP).
- **Visibility**: Private — attached to the host VPC network(s).
- **Location**: Regional or global (private zones can be regional if desired, but global is simpler for multi-region).

Example friendly name per endpoint:  
`vs-<team>-<workload>-<region>.mycompany.internal` → A record to `<PSC_IP>`

## Leveraging Existing Self-Service DNS

We already have a self-service portal/console for creating DNS records (CNAME/A) — originally built for GKE Istio virtual services and internal load balancer IPs.

This **exact same self-service** can be used for Vector Search PSC endpoints:

- **Record Type**: A (not CNAME — since we have a direct IP, not a hostname to alias).
- **Inputs from app team** (after Vector Search deployment via console):
  - Custom domain/hostname: e.g., `vs-myapp-us-central1.mycompany.internal`
  - Target: The PSC internal IP (displayed in the Vector Search console post-deployment)
  - TTL: 300–3600 seconds (standard)
  - Zone: The private zone(s) already managed (e.g., `mycompany.internal`)
- No special approvals needed beyond existing process.
- Self-service link: [Insert actual link here, e.g., https://console.mycompany.com/dns-selfservice or internal portal URL]

This keeps things consistent — app teams already know the flow from GKE/ILB usage.

## One-Time Setup Steps (Networking Team)

If not already done for other PSC/internal services:

1. **Create Private Managed Zone** (if a suitable private zone doesn't exist yet):
   ```bash
   gcloud dns managed-zones create vectorsearch-private-zone \
     --dns-name="mycompany.internal." \
     --description="Private DNS for internal services including Vector Search PSC" \
     --visibility=private \
     --networks="https://www.googleapis.com/compute/v1/projects/HOST_PROJECT/global/networks/HOST_VPC" \
     --project=HOST_PROJECT

Attach to all relevant host VPCs (non-prod/prod).
Use regional zone if you prefer per-region isolation.


Enable Cloud DNS API (if not already): In host project.
Verify Zone Attachment: Ensure the zone is visible/usable from service projects via Shared VPC (DNS resolution inherits from host network).
Communicate to App Teams:
Update internal wiki/Confluence with: "For Vector Search PSC friendly names, use the standard DNS self-service tool with A records pointing to the PSC IP shown in the deployment console."
No need for wildcard or special zones per endpoint — per-hostname A records are fine and handled by self-service.


No Changes Needed for Automation/Console Team

DNS is post-deployment and optional.
Console returns the raw PSC IP (and perhaps suggests the friendly name format).
No Terraform resources for DNS in the Vector Search module.
If app teams skip DNS → they use IP directly or SDK psc_network param (still fully functional).

References

Cloud DNS Private Zones: https://cloud.google.com/dns/docs/zones#creating-a-private-zone
Adding Records to Private Zones: https://cloud.google.com/dns/docs/records
Vertex AI Vector Search PSC (mentions optional DNS record for friendly name): https://cloud.google.com/vertex-ai/docs/vector-search/private-service-connect
PSC General DNS Guidance: https://cloud.google.com/vpc/docs/configure-private-service-connect-services#other-dns

This one-time setup enables a smooth, consistent experience without adding complexity to the core Vector Search automation.
