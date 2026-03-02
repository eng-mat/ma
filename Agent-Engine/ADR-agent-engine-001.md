# ADR-AgentEngine-001: Self-Service Private Vertex AI Agent Engine with PSC Interface, CMEK, and Mandatory Zscaler Egress

**Status:** Draft  
**Date:** March 02, 2026  
**Author:** Matthew (GCP Engineering Team)  
**Reviewers:** Architecture, Security, Automation, Networking

## Context

Our GCP environment is fully private — no public IPs. We use **Shared VPC** with dedicated host projects for non-prod and prod. Subnets are shared to service projects. All internet egress routes through Zscaler via network tags and Cloud NAT. We rely on **Private Service Connect Interface (PSC-I)** for services requiring bidirectional private connectivity, and avoid peering.

App teams need **Vertex AI Agent Engine** (part of Agent Builder) for agentic workflows that call internal services (GKE, Cloud Run, internal APIs, databases, etc.). Direct creation is restricted — only the Automation service account can deploy/update.

This self-service must:
- Stay **100% private**.
- Enforce **CMEK** on compatible resources.
- Force **all internet egress** through Zscaler (no direct internet from agent runtime).
- Support creation, updates, scaling, and deletion.
- Work across our regions and host VPCs (non-prod/prod).
- Allow seamless addition of more PSC-I subnets in future.
- Align with Google’s latest PSC-I guidance and enterprise security standards.

## Decision

We will deliver **Vertex AI Agent Engine** using **Private Service Connect Interface (PSC-I)** + mandatory **CMEK** + explicit **Zscaler-tagged proxy VM/MIG** for egress.

- PSC-I attachment created in service project (Google recommendation).
- One-time large PSC-I subnet per host/region (shared via Shared VPC).
- Network attachment supports multiple subnets (future-proof).
- Internet egress forced through a dedicated proxy VM/MIG (tagged for Zscaler) — no direct internet allowed.
- Proxy setup documented separately for manual/Cloud Eng execution.

## Detailed Architecture

### 1. High-Level Components
- **Agent Engine** resource in service project.
- **PSC Interface** via Network Attachment (in service project).
- **Proxy VM/MIG** in host project (for Zscaler egress).
All resources in service project except one-time subnet and proxy in host.

### 2. Network Design (Private-Only)
- **One-time per host project per region** (Cloud Engineering):
  - Create large PSC-I subnet (e.g. /20) — shared to service projects.
  - Design supports adding more PSC-I subnets later (Network Attachment can reference multiple).

- **Per-service-project / per-deployment**:
  - Create Network Attachment referencing the PSC-I subnet(s).
  - Example Terraform snippet (conceptual):
    ```hcl
    resource "google_compute_network_attachment" "agentengine_attachment" {
      name   = "agentengine-psc-attachment-${var.region}"
      region = var.region
      subnetwork {
        subnetwork = "projects/${var.host_project}/regions/${var.region}/subnetworks/psc-i-agentengine-${var.region}"
      }
      # Future: add more subnetwork blocks for additional PSC-I subnets
      connection_preference = "ACCEPT_AUTOMATIC"
    }

Agent Engine deploys with:YAMLpsc_interface_config:
  network_attachment: "projects/${SERVICE_PROJECT}/regions/${REGION}/networkAttachments/agentengine-psc-attachment-${REGION}"
Internal traffic (GKE, Cloud Run, on-prem) routes transitively via PSC-I.
Internet traffic: Forced through explicit proxy VM/MIG IP (configured in agent).

3. Egress (Mandatory Zscaler)

No direct internet from Agent Engine runtime.
All non-RFC1918 traffic routes to proxy VM/MIG IP (e.g. HTTP_PROXY=http://proxy-ip:3128).
Proxy VM/MIG uses existing Zscaler network tag → follows current path: proxy → Zscaler Connector → Cloud NAT → Zscaler Cloud → Internet.
Proxy setup: See separate document Proxy-Setup-AgentEngine-OneTime.md (manual/Cloud Eng steps after VM/MIG deployment).
Use existing VM automation where possible.
Prefer Managed Instance Group (MIG) for HA (auto-healing, zonal spread).
Separate subnet for MIG recommended (e.g. proxy-agentengine-us-central1).
Proxy listens on standard port (e.g. 3128), allow from PSC-I subnet range(s).


4. Encryption (CMEK Mandatory)
YAMLencryptionSpec:
  kmsKeyName: "projects/$$   {SERVICE_PROJECT}/locations/   $${REGION}/keyRings/$$   {KEYRING}/cryptoKeys/   $${KEY}"

Use existing per-project CMEK key from centralized vault.
Grant AI Platform service agent roles/cloudkms.cryptoKeyEncrypterDecrypter on the key.

5. IAM & Security

Host project (one-time / automated):
Add AI Platform service agent (service-<number>@gcp-sa-aiplatform.iam.gserviceaccount.com) to local group (already has roles/compute.networkUser + roles/dns.peer).

Service project (per-deployment):
Assign org-level custom role + roles/dns.peer to AI Platform service agent.

Full audit logging + VPC-SC compatibility.

6. Required APIs (Enabled in Service Project)

aiplatform.googleapis.com
vertexai.googleapis.com
compute.googleapis.com
dns.googleapis.com
networkconnectivity.googleapis.com

7. Firewall Rules (Host VPC – one-time)

Allow PSC-I subnet range(s) → internal workloads (GKE, Cloud Run, VMs, databases).
Allow PSC-I subnet range(s) → proxy VM/MIG port (e.g. 3128).
Proxy VM/MIG already tagged for Zscaler egress.

8. DNS

Automatic DNS peering configured at deployment (dns_peering_configs).
Friendly names (optional): Use existing self-service DNS portal (A record to PSC interface IP or proxy IP if needed).
One-time private zone (if desired): See separate DNS doc.

9. Self-Service Capabilities (Automation Must Support)

Region / host VPC selection.
Scaling (max_instances).
CMEK key selection/validation.
Proxy IP (pre-filled or parameterized).
Internal endpoints to allow.
Return PSC interface IP + proxy details.
Support updates/redeploys.

10. Observability & Cost

Vertex AI metrics/logging.
Dashboards: agent latency, QPS, errors.
Labels for cost allocation.
Alerts on scaling failures, quota issues.

Alternatives Considered

Secure Web Proxy (SWP): Rejected — duplicates Zscaler inspection, adds complexity/cost.
Direct internet egress: Rejected — violates policy.
Network Attachment in host: Rejected — Google recommends service project.

Risks & Mitigations

IP exhaustion: Large /20 subnet + monitoring; expandable.
Proxy single point: Use MIG with health checks.
Future PSC-I subnets: Attachment supports multiple; firewall uses range or tags.
First deployment delay: Pre-check attachment/group membership.

References (Official Google Cloud Docs + Terraform)

Vertex AI Agent Engine Overview: https://cloud.google.com/vertex-ai/docs/generative-ai/agents/overview
Private Service Connect Interface for Vertex AI: https://cloud.google.com/vertex-ai/docs/general/psc-interfaces
Set up PSC-I for Agent Engine: https://cloud.google.com/vertex-ai/docs/general/vpc-psc-i-setup
CMEK for Vertex AI: https://cloud.google.com/vertex-ai/docs/general/cmek
Terraform: google_compute_network_attachment: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_attachment
Terraform: google_vertex_ai_agent: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/vertex_ai_agent (adapt for Agent Engine)
Secure egress with proxy: https://cloud.google.com/architecture/secure-internet-egress-hybrid

Next Steps for Automation Team

Terraform module: Enable APIs → IAM (custom role + dns.peer) → Network Attachment → CMEK grant → Agent Engine deploy (PSC-I + proxy config + DNS peering).
Parameterize: region, host project, proxy IP, CMEK key.
Pre-checks: attachment existence, group membership, quotas, key access.
Return PSC interface IP + proxy details to console.

Proxy Setup: See Proxy-Setup-AgentEngine-OneTime.md for manual steps (VM/MIG deployment, proxy config, MIG health checks, etc.).
This provides a secure, private, Zscaler-enforced Agent Engine pattern that fits our enterprise constraints.
