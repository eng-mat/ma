# ADR-AgentEngine-001: Self-Service Private Vertex AI Agent Engine with PSC Interface, CMEK, Mandatory Zscaler Egress (HTTPS-Only), and Optional Friendly DNS Name

**Status:** Draft  
**Date:** March 02, 2026  
**Author:** (GCP Engineering Team)  
**Reviewers:** Architecture, Security, Automation, Networking

## Context

Our GCP environment is fully private — no public IPs. Shared VPC with dedicated host projects for non-prod and prod. Subnets shared to service projects. All internet egress routes through Zscaler via network tags and Cloud NAT. We use Private Service Connect Interface (PSC-I) for bidirectional private connectivity.

App teams need Vertex AI Agent Engine for tool calling, function calling, grounding with internal sources (Vector Search, Cloud SQL, etc.), multi-agent workflows, RAG, and direct calls to GKE, Cloud Run, internal APIs, on-prem, etc. Direct creation is restricted — only Automation service account can deploy/update.

This self-service must:
- Stay 100% private
- Enforce CMEK on compatible resources
- Route outbound/internet traffic through Zscaler using HTTPS-only (no HTTP, no direct internet)
- Support full CRUD + scaling
- Work across regions and host VPCs
- Allow additional PSC-I subnets later
- Offer optional friendly DNS name at deployment (for PSC IP or SWP hostname) — or later via existing DNS portal
- Align with Google’s latest PSC-I and security guidance

## Decision

Deliver Vertex AI Agent Engine using **Private Service Connect Interface (PSC-I)** + mandatory **CMEK** + **Secure Web Proxy (SWP)** in explicit forward mode (HTTPS-only on port 3128, upstream to Zscaler — no SWP inspection).

Key points:
- PSC-I attachment in service project
- One-time large PSC-I subnet per host/region (shared)
- One-time proxy-only subnet + SWP gateway per region
- Network attachment supports multiple subnets
- Internal traffic direct via PSC-I — outbound/internet traffic to SWP only when configured
- Optional friendly DNS name during deployment: app team provides hostname → Automation creates A record in host private zone (target = PSC IP for internal, or SWP hostname/IP for outbound if selected)
- If skipped: raw PSC IP shown + link to existing DNS self-service portal (GKE-style workflow)

## Detailed Architecture

### 1. High-Level Components
- Agent Engine resource in service project (full feature set)
- PSC Interface via Network Attachment (service project)
- Secure Web Proxy gateway in host project (pass-through to Zscaler)

### 2. Network Design (Private-Only & Future-Proof)
- One-time per host project per region (Cloud Engineering):
  - Large PSC-I subnet (e.g. /20) — shared
  - Proxy-only subnet (purpose=REGIONAL_MANAGED_PROXY)
  - Supports adding more PSC-I subnets later

- Per-service-project / per-deployment:
  - Network Attachment referencing PSC-I subnet(s) (multiple supported)
  - Agent Engine configured with:
    ```yaml
    psc_interface_config:
      network_attachment: "projects/${SERVICE_PROJECT}/regions/${REGION}/networkAttachments/agentengine-psc-attachment-${REGION}"

    Internal traffic routes transitively via PSC-I
Outbound/internet traffic: only when app team sets HTTPS_PROXY to regional SWP hostname (see section 3)

3. **Egress (Mandatory Zscaler — HTTPS-Only, Optional)**

- No direct internet from Agent Engine runtime
- Internal-only agents: No SWP needed — traffic stays private via PSC-I
- Outbound/internet traffic (when required): App team configures explicit HTTPS_PROXY to regional SWP hostname (e.g. http://agentengine-swp-us-- central1.mycompany.internal:3128)
- **SWP:**
  - Listens only on port 3128
  - Explicit forward mode with upstream to Zscaler (no inspection/decryption)
  - Allows HTTPS only (CONNECT to 443)
  - Rejects plain HTTP

- **SWP setup: See Proxy-Setup-AgentEngine-OneTime.md**

4. **Encryption (CMEK Mandatory)**
encryptionSpec:
  kmsKeyName: "projects/$$   {SERVICE_PROJECT}/locations/   $${REGION}/keyRings/$$   {KEYRING}/cryptoKeys/   $${KEY}"

- Existing per-project CMEK key from vault
- AI Platform service agent granted roles/cloudkms.cryptoKeyEncrypterDecrypter

5. **IAM & Security**

- Host project: AI Platform service agent in local group (compute.networkUser + dns.peer)
- Service project: Org-level custom role + roles/dns.peer

6. **Required APIs (Service Project)**

- aiplatform.googleapis.com
- vertexai.googleapis.com
- compute.googleapis.com
- dns.googleapis.com
- networkconnectivity.googleapis.com

7. **Firewall Rules (Host VPC — one-time)**

- PSC-I subnet range(s) → internal workloads
- PSC-I subnet range(s) → SWP on port 3128 only

8. **DNS (Optional Friendly Name at Deployment)**

- Automatic DNS peering via dns_peering_configs (app team configures for internal domains)
- Optional friendly name during self-service creation:
- App team provides desired hostname (e.g. agent-myapp-us-central1.mycompany.internal)
- Optional outbound indicator (checkbox: "This agent needs internet egress")
- Automation creates A record in host private DNS zone:
    - If outbound not selected → target = PSC interface IP
    - If outbound selected → target = SWP hostname/IP (or both if they want two names)

- If skipped: Console shows raw PSC IP + link to existing DNS self-service portal

- One-time private zone attachment: See DNS-AgentEngine-OneTime.md

9. **Self-Service Capabilities (Automation Must Support)**

- Full Agent Engine feature set
- Region/host selection, scaling (max_instances), CMEK validation
- Optional friendly DNS name input (text field + validation: ends with .mycompany.internal)
- Optional outbound checkbox (shows HTTPS_PROXY suggestion only if checked)
- HTTPS_PROXY suggestion: Pre-fill regional SWP hostname (e.g. agentengine-swp-${region}.mycompany.internal:3128) — only shown if outbound needs indicated
- Updates/redeploys supported

10. **Observability & Cost**

- Vertex AI metrics/logging
- Labels for cost allocation
- Alerts on scaling, latency, quota

**Alternatives Considered**

- VM/MIG proxy: Rejected — patching, approval issues
- Direct egress / HTTP allowed: Rejected — violates policy
- Mandatory DNS name: Rejected — must be optional

**Risks & Mitigations**

- IP exhaustion: Large /20 + monitoring
- SWP availability: Managed regional service
- DNS name conflicts: Automation validates uniqueness
- Misconfiguration of outbound: Console guidance + optional outbound checkbox

**References**

- Vertex AI Agent Engine Overview: https://cloud.google.com/vertex-ai/docs/generative-ai/agents/overview
- PSC Interface for Agent Engine: https://cloud.google.com/vertex-ai/docs/general/psc-interfaces
- Set up PSC-I: https://cloud.google.com/vertex-ai/docs/general/vpc-psc-i-setup
- Secure Web Proxy (explicit + upstream): https://cloud.google.com/secure-web-proxy/docs/explicit-proxy
- CMEK: https://cloud.google.com/vertex-ai/docs/general/cmek
- Terraform: google_compute_network_attachment: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_attachment

**Next Steps for Automation Team**

- Terraform: APIs → IAM → Network Attachment → CMEK → Agent Engine (PSC-I + optional dns_peering_configs + optional A record creation)
- Add optional inputs: friendly_domain (string, validation: ends with .mycompany.internal), outbound_needed (boolean)
- If friendly_domain provided: Create A record via Cloud DNS API (Automation SA needs dns.admin or delegated permissions)
    - Target: PSC IP (default) or SWP hostname/IP if outbound_needed checked
- Parameterize: region, SWP hostname (port 3128), CMEK key, optional friendly_domain/outbound_needed
- Pre-checks: attachment, group membership, key access, DNS zone existence
- Return PSC IP + friendly name (if created) + SWP details

**Proxy Setup: See Proxy-Setup-AgentEngine-OneTime.md**
This gives app teams maximum flexibility: internal-only agents get simple private access, outbound agents get clean egress, and DNS names are optional at deploy time or later via the existing portal.
