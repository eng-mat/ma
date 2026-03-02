# ADR-AgentEngine-001: Self-Service Private Vertex AI Agent Engine with PSC Interface, CMEK, and Mandatory Zscaler Egress (HTTPS-Only)

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
- Support creation, updates, scaling, and deletion
- Work across our regions and host VPCs
- Seamlessly support additional PSC-I subnets in future
- Align with Google’s latest PSC-I guidance and enterprise security standards

## Decision
We will deliver **Vertex AI Agent Engine** using **Private Service Connect Interface (PSC-I)** + mandatory **CMEK** + **Secure Web Proxy (SWP)** in explicit forward mode (HTTPS-only on port 3128, upstream to Zscaler).

- PSC-I attachment created in service project
- One-time large PSC-I subnet per host/region (shared)
- One-time proxy-only subnet and SWP gateway per region
- Network attachment supports multiple subnets (future-proof)
- Internal traffic routes directly via PSC-I (no SWP)
- Outbound/internet traffic (when needed) routes through SWP (HTTPS-only, port 3128) — app team configures explicitly
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
SWP setup: See separate document Proxy-Setup-AgentEngine-OneTime.md (Cloud Engineering handles proxy-only subnet, SWP gateway creation, upstream config to Zscaler, HTTPS-only enforcement on 3128)
4. Encryption (CMEK Mandatory)
YAML
encryptionSpec:
  kmsKeyName: "projects/$$   {SERVICE_PROJECT}/locations/   $${REGION}/keyRings/$$   {KEYRING}/cryptoKeys/   $${KEY}"
Uses existing per-project CMEK key from centralized vault
AI Platform service agent granted roles/cloudkms.cryptoKeyEncrypterDecrypter
5. IAM & Security
Host project: Add AI Platform service agent to local group (already has compute.networkUser + dns.peer)
Service project: Assign org-level custom role + roles/dns.peer to AI Platform service agent
6. Required APIs (Service Project)
aiplatform.googleapis.com
vertexai.googleapis.com
compute.googleapis.com
dns.googleapis.com
networkconnectivity.googleapis.com
7. Firewall Rules (Host VPC — one-time)
PSC-I subnet range(s) → internal workloads (GKE/Cloud Run/VMs/databases)
PSC-I subnet range(s) → SWP on port 3128 only
8. DNS
Automatic DNS peering at deployment
Friendly names (optional): Use existing self-service DNS portal (A record to PSC interface IP)
9. Self-Service Capabilities (Automation Must Support)
Full Agent Engine feature set (all use cases: tool calling, grounding, multi-agent workflows, internal service integrations)
Region/host selection, scaling (max_instances), CMEK validation
Optional outbound/internet checkbox (shows pre-filled regional SWP hostname suggestion only if checked)
Updates/redeploys supported
10. Observability & Cost
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
References
Vertex AI Agent Engine Overview: https://cloud.google.com/vertex-ai/docs/generative-ai/agents/overview
PSC Interface for Agent Engine: https://cloud.google.com/vertex-ai/docs/general/psc-interfaces
Set up PSC-I: https://cloud.google.com/vertex-ai/docs/general/vpc-psc-i-setup
Secure Web Proxy (explicit mode + upstream): https://cloud.google.com/secure-web-proxy/docs/explicit-proxy
CMEK: https://cloud.google.com/vertex-ai/docs/general/cmek
Terraform: google_compute_network_attachment: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_attachment
Next Steps for Automation Team
Terraform: APIs → IAM → Network Attachment (multi-subnet support) → CMEK → Agent Engine (PSC-I + optional HTTPS_PROXY + DNS peering)
Parameterize: region, SWP hostname (port 3128), CMEK key
Pre-checks: attachment, group membership, key access
Return PSC IP + SWP details
Proxy Setup: See Proxy-Setup-AgentEngine-OneTime.md (Cloud Engineering to handle proxy-only subnet, SWP gateway creation, upstream to Zscaler, HTTPS-only config on port 3128).
This design supports all Agent Engine use cases while enforcing private connectivity, CMEK, and strict HTTPS-only Zscaler egress (via managed Secure Web Proxy — no double inspection).

Proxy Setup: See Proxy-Setup-AgentEngine-OneTime.md (Cloud Engineering to handle proxy-only subnet, SWP gateway creation, upstream to Zscaler, HTTPS-only config on port 3128).
This design supports all Agent Engine use cases while enforcing private connectivity, CMEK, and strict HTTPS-only Zscaler egress (via managed Secure Web Proxy — no double inspection).
