# ADR-AgentEngine-001: Self-Service Private Vertex AI Agent Engine with PSC Interface, CMEK, Mandatory Zscaler Egress (HTTPS-Only), and VPC Service Controls

**Status:** Draft
**Date:** March 02, 2026
**Author:** Matthew (GCP Engineering Team)
**Reviewers:** Architecture, Security, Automation, Networking

## Context
Our GCP environment is fully private — no public IPs. We use **Shared VPC** with dedicated host projects for non-prod and prod. Subnets are shared to service projects. All internet egress routes through Zscaler via network tags and Cloud NAT. We rely on **Private Service Connect Interface (PSC-I)** for bidirectional private connectivity.

App teams need **Vertex AI Agent Engine** for all use cases: tool calling, function calling, grounding with internal data sources (Vector Search, Cloud SQL, etc.), multi-agent workflows, RAG, and direct calls to GKE/Cloud Run/internal APIs. Direct creation is restricted — only the Automation service account can deploy/update.

This self-service must:
- Stay **100% private**
- Enforce **CMEK** on compatible resources
- Route outbound/internet traffic through Zscaler using **HTTPS-only** (no HTTP allowed) — internal traffic stays direct via PSC-I
- Prevent any direct egress from the Google-managed tenant using **VPC Service Controls**
- Support creation, updates, scaling, and deletion
- Work across our regions and host VPCs
- Seamlessly support additional PSC-I subnets in future
- Align with Google’s latest PSC-I guidance and enterprise security standards

## Decision
We will deliver **Vertex AI Agent Engine** using **Private Service Connect Interface (PSC-I)** + mandatory **CMEK** + **Secure Web Proxy (SWP)** in explicit forward mode (HTTPS-only on port 3128, upstream to Zscaler) + **VPC Service Controls** perimeter on every project that uses Agent Engine.

- PSC-I attachment created in service project
- One-time large PSC-I subnet per host/region (shared)
- One-time proxy-only subnet and SWP gateway per region
- Network attachment supports multiple subnets (future-proof)
- Internal traffic routes directly via PSC-I (no SWP)
- Outbound/internet traffic (when needed) routes through SWP — app team configures explicitly
- VPC-SC perimeter blocks any direct egress from the Google tenant and enforces that only approved APIs inside the perimeter can be called
- SWP setup documented separately for Cloud Engineering to implement

## Detailed Architecture

### 1. High-Level Components
- **Agent Engine** resource in service project (supports all use cases: tool/function calling, grounding, multi-agent workflows, internal service integrations)
- **PSC Interface** via Network Attachment (service project)
- **Secure Web Proxy (SWP)** gateway in host project (Zscaler egress pass-through)

### 2. Network Design (Private-Only & Future-Proof)
- **One-time per host project per region** (Cloud Engineering):
  - Create large PSC-I subnet (e.g. /20) — shared
  - Create proxy-only subnet (purpose=REGIONAL_MANAGED_PROXY)
  - Design supports adding more PSC-I subnets later
- **Per-service-project / per-deployment**:
  - Create Network Attachment referencing PSC-I subnet(s) (multiple supported)
  - Agent Engine configured with:
    ```yaml
    psc_interface_config:
      network_attachment: "projects/${SERVICE_PROJECT}/regions/${REGION}/networkAttachments/agentengine-psc-attachment-${REGION}"

Internal traffic (GKE, Cloud Run, on-prem) routes transitively via PSC-I
Outbound/internet traffic: Only when app team configures HTTPS_PROXY to regional SWP hostname (see section 3)

3. Egress (Mandatory Zscaler — HTTPS-Only, Optional)
No direct internet from Agent Engine runtime
Internal-only agents: No SWP needed — traffic stays private via PSC-I
Outbound/internet traffic (when required): App team configures explicit HTTPS_PROXY to regional SWP hostname (pre-filled in console based on region/host)
Secure Web Proxy:
Listens only on port 3128
Configured in explicit forward mode with upstream proxy pointing to Zscaler (no SWP inspection, filtering, or decryption)
Allows HTTPS traffic only (CONNECT method to destination port 443)
Rejects all plain HTTP (port 80)
Uses existing Zscaler path via Cloud NAT and network tag configuration

SWP setup: See separate document Proxy-Setup-AgentEngine-OneTime.md

4. VPC Service Controls (Mandatory Security Perimeter)
To prevent any possible direct egress from the Google-managed tenant (even before SWP is hit), every project using Agent Engine must be placed inside a VPC Service Controls perimeter:

We will use (or create) a dedicated AI Services Perimeter (recommended single perimeter for all AI workloads)
When a project is added:
aiplatform.googleapis.com and vertexai.googleapis.com are automatically added to restricted services
Any other Google APIs the agent needs (BigQuery, Cloud Storage, Cloud Run, etc.) must also be added to the perimeter

Automation will:
Add the service project to the perimeter during deployment
Validate and add required APIs
Support adding more projects later (via console or Ops GitHub Actions workflow)

Cross-perimeter scenario: If the agent needs a resource in another perimeter, that resource’s project must also be added to the same AI perimeter (or we create ingress/egress rules). This will be handled as part of the same self-service flow with a pre-flight check.
This combination (VPC-SC + SWP) guarantees zero direct internet egress from the Google tenant.

5. Encryption (CMEK Mandatory)
YAMLencryptionSpec:
  kmsKeyName: "projects/$$   {SERVICE_PROJECT}/locations/   $${REGION}/keyRings/$$   {KEYRING}/cryptoKeys/   $${KEY}"

Uses existing per-project CMEK key from centralized vault
AI Platform service agent granted roles/cloudkms.cryptoKeyEncrypterDecrypter

6. IAM & Security
Host project: Add AI Platform service agent to local group (already has compute.networkUser + dns.peer)
Service project: Assign org-level custom role + roles/dns.peer to AI Platform service agent

7. Required APIs (Service Project)
aiplatform.googleapis.com
vertexai.googleapis.com
compute.googleapis.com
dns.googleapis.com
networkconnectivity.googleapis.com
Any other APIs the agent will call (added to VPC-SC perimeter)

8. Firewall Rules (Host VPC — one-time)
PSC-I subnet range(s) → internal workloads (GKE/Cloud Run/VMs/databases)
PSC-I subnet range(s) → SWP on port 3128 only

9. DNS
Automatic DNS peering at deployment
Friendly names (optional): Use existing self-service DNS portal (A record to PSC interface IP)

10. Self-Service Capabilities (Automation Must Support)
Full Agent Engine feature set (all use cases: tool calling, grounding, multi-agent workflows, internal service integrations)
Region/host selection, scaling (max_instances), CMEK validation
Optional outbound/internet checkbox (shows pre-filled regional SWP hostname only if checked)
Updates/redeploys supported

11. Observability & Cost
Vertex AI metrics/logging
Labels for cost allocation
Alerts on scaling, latency, quota

Alternatives Considered
VM/MIG proxy: Rejected — patching, open-source software approval, operational overhead
Direct egress / HTTP allowed: Rejected — violates policy

Risks & Mitigations
IP exhaustion: Large /20 + monitoring
SWP availability: Regional managed service with built-in redundancy
Future PSC-I subnets: Attachment and firewall support multiple ranges
HTTPS-only enforcement: Handled at SWP level
Project not in VPC-SC: Automation pre-flight check blocks deployment

References
Vertex AI Agent Engine Overview: https://cloud.google.com/vertex-ai/docs/generative-ai/agents/overview
PSC Interface for Agent Engine: https://cloud.google.com/vertex-ai/docs/general/psc-interfaces
Set up PSC-I: https://cloud.google.com/vertex-ai/docs/general/vpc-psc-i-setup
Secure Web Proxy (explicit mode + upstream): https://cloud.google.com/secure-web-proxy/docs/explicit-proxy
VPC Service Controls with Vertex AI: https://cloud.google.com/vertex-ai/docs/general/vpc-service-controls
CMEK: https://cloud.google.com/vertex-ai/docs/general/cmek
Terraform: google_compute_network_attachment: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_attachment

Next Steps for Automation Team
Terraform: APIs → IAM → Network Attachment (multi-subnet support) → CMEK → Add project + required APIs to VPC-SC perimeter → Agent Engine (PSC-I + optional HTTPS_PROXY + DNS peering)
Parameterize: region, SWP hostname (port 3128), CMEK key, list of additional APIs if needed
Pre-checks: attachment, group membership, key access, VPC-SC perimeter membership
Return PSC IP + SWP details

Proxy Setup: See Proxy-Setup-AgentEngine-OneTime.md (Cloud Engineering to handle proxy-only subnet, SWP gateway creation, upstream to Zscaler, HTTPS-only config on port 3128).
This design supports all Agent Engine use cases while enforcing private connectivity, CMEK, strict HTTPS-only Zscaler egress, and VPC Service Controls to block any direct egress from the Google tenant (via managed Secure Web Proxy — no double inspection).
