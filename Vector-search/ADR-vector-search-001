ADR-VectorSearch-001: Self-Service Private Vertex AI Vector Search (Index + Index Endpoint) with Private Service Connect and CMEK

Status: Draft
Date: March 01, 2026
Author: (GCP Engineering Team)
Reviewers: Architecture, Security, Automation

Context
Our GCP environment is fully private — no public IPs anywhere. We use Shared VPC with dedicated host projects for non-prod and prod environments. Subnets from host projects are shared to service projects. All internet egress routes through Zscaler (via tags + Cloud NAT). We rely on Private Service Connect (PSC) for Google APIs and services, plus serverless VPC connectors where required. We avoid VPC peering in favor of PSC wherever possible.

App teams need Vector Search for use cases like RAG, semantic search, recommendations, similarity matching, etc. Direct creation of Vector Search resources is blocked enterprise-wide by Cloud Security — only the Automation service account is allowed to create/update them.

This self-service offering (via console for app teams, or internal GitHub Actions for Operations) must:
- Stay 100% private with no public exposure.
- Enforce CMEK on all compatible resources (Index and Index Endpoint).
- Allow creation, updates (redeploy, config changes), and deletion.
- Work across our supported regions.
- Follow Google's latest private Vector Search guidance and enterprise security standards.
- Fit our existing Shared VPC and Zscaler egress model.

Decision
We will deliver Vertex AI Vector Search using **Private Service Connect in automated mode** + mandatory **CMEK**.

This uses the official automated PSC flow: we (Cloud Engineering) create a one-time Service Connection Policy per relevant host VPC/region, then deployments automatically provision the internal IP and forwarding rule. No manual network resources per endpoint. This is cleaner, less error-prone, and matches our preference for PSC over peering or manual setup.

Detailed Architecture

1. High-Level Components
- Index: Stores embeddings (batch upload or streaming).
- Index Endpoint: Serves queries via PSC.
- Deployed Index: One or more indexes attached to the endpoint.
All resources live in the **service project** (consumer/app project).
Network config references the **host project** VPC/network.

2. Network Design (Private-Only)
- At Index Endpoint creation, set:
  - privateServiceConnectConfig.enablePrivateServiceConnect = true
  - privateServiceConnectConfig.projectAllowlist = [list of our host project IDs]
- Prerequisite (one-time, handled by Cloud Engineering):
  - Create a Service Connection Policy in each relevant host VPC/region for service-class = gcp-vertexai.
  - Example (not for Automation to run — this is pre-setup):
    gcloud network-connectivity service-connection-policies create vectorsearch-policy-us-central1 \
      --project=HOST_PROJECT \
      --network=projects/HOST_PROJECT/global/networks/HOST_NETWORK \
      --service-class=gcp-vertexai \
      --region=us-central1 \
      --subnets=psc-subnet-us-central1
  - This policy must exist before any automated deployments in that region/network.
  - Once the policy is in place, Vertex AI automatically provisions:
    - Regional internal IP from the designated PSC subnet.
    - Forwarding rule in the host VPC.
- No per-deployment manual compute addresses or forwarding rules needed.
- Queries from VMs/GKE/Cloud Run/etc. in the Shared VPC reach the endpoint via the auto-provisioned internal IP.
- Hybrid/on-prem access works via our existing HA VPN/Interconnect (route the PSC IP range).
- All traffic stays private — no internet egress for index serving or queries.

DNS Requirements
No per-deployment DNS setup required in automation.
- The Vertex AI SDK (Python/gRPC) handles resolution automatically when you specify the psc_network parameter (projects/HOST_PROJECT/global/networks/HOST_NETWORK).
- If teams want friendly names (e.g. vs-endpoint-us-central1.mycompany.internal), we can create a one-time private Cloud DNS managed zone in the host project(s) pointing to the PSC IP pattern.
- This one-time DNS setup is **out of scope** for the Terraform module and will be documented separately (DNS-VectorSearch-OneTime.md) for the Networking team.

3. Encryption (CMEK Mandatory)
Every CMEK-compatible resource **must** use customer-managed encryption:
- Index and Index Endpoint:
  encryptionSpec:
    kmsKeyName: "projects/SERVICE_PROJECT/locations/REGION/keyRings/KEYRING/cryptoKeys/KEY"
- Use the same key for Index and Endpoint.
- Keys already exist per project in centralized vault — no creation/rotation steps in this flow.
- This covers embeddings in underlying storage and any internal data.

4. IAM & Security
- Only Automation service account creates/updates/deploys (enforced by policy).
- Automation SA needs (in service project):
  - roles/aiplatform.admin (or scoped: indexAdmin + indexEndpointAdmin)
  - roles/compute.networkUser on host VPC (for PSC automation)
- App teams get query/read access via custom roles.
- Project allowlist restricts to our host projects only.
- Full audit logging via Cloud Audit Logs + Vertex AI logs.
- If inside VPC-SC perimeter, ensure aiplatform.googleapis.com is allowed.

5. Self-Service Capabilities (Automation Must Support)
Console/GitHub form must allow:
- Create new Index (batch/streaming config).
- Create/Update Index Endpoint (PSC + CMEK + allowlist).
- Deploy indexes to endpoint (with replica count, min replicas, etc.).
- Update index data or config (rebuild/add/remove).
- Add/remove deployed indexes.
- Delete with confirmations.
Terraform module must handle updates (most fields mutable except displayName — enforce naming convention like vs-team-workload-region).

6. Querying from Applications
App teams:
1. Get PSC internal IP from console post-deployment.
2. Preferred: Use SDK with psc_network param — auto-resolves.
3. Call match() or gRPC on port 10000 against the IP.

Works from any Shared VPC workload.

7. Observability, Monitoring & Cost
- Enable Vertex AI metrics/logging.
- Dashboards: latency, QPS, index size.
- Labels: team, env, workload for cost allocation.
- Alerts: high latency, rebuild failures, quota issues.

8. Disaster Recovery & Availability
- Indexes durable in regional storage.
- Configurable replicas on deployment.
- Regional endpoints — select region in self-service.
- Cross-region replication as future option if needed.

Alternatives Considered
- Manual PSC (create forwarding rule per endpoint): Rejected — more steps, error-prone.
- VPC Network Peering: Rejected — we avoid peering.
- Public endpoints: Rejected — violates private policy.

Risks & Mitigations
- Service Connection Policy missing → Automation pre-check + console validation.
- One IP per project per network limit → Allow multiple endpoints; document clearly.
- DisplayName immutable → Enforce strict naming in console.
- CMEK key missing → Pre-flight check in automation.
- Quotas (forwarding rules, etc.) → Include quota checks.

References (Official Google Cloud Docs + Terraform Resources)
Vertex AI Vector Search Overview: https://cloud.google.com/vertex-ai/docs/vector-search/overview
Set up Vector Search with Private Service Connect: https://cloud.google.com/vertex-ai/docs/vector-search/private-service-connect
Use Private Service Connect to access a Vector Search index from on-premises: https://cloud.google.com/vertex-ai/docs/general/vertex-psc-vector-search
About accessing Vertex AI services through Private Service Connect endpoints: https://cloud.google.com/vertex-ai/docs/general/psc-endpoints
Customer-managed encryption keys (CMEK) for Vertex AI (including Vector Search Index/Endpoint): https://cloud.google.com/vertex-ai/docs/general/cmek
Manage indexes (includes batch/streaming, updates): https://cloud.google.com/vertex-ai/docs/vector-search/create-manage-index
Deploy and manage public index endpoints (adapt for private): https://cloud.google.com/vertex-ai/docs/vector-search/deploy-index-public
Query private indexes (SDK + PSC usage): https://cloud.google.com/vertex-ai/docs/vector-search/query-index-vpc
Terraform support for Vertex AI (full list of resources): https://cloud.google.com/vertex-ai/docs/start/use-terraform-vertex-ai
Terraform: google_vertex_ai_index (core index creation, metadata, config, CMEK support): https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/vertex_ai_index
Terraform: google_vertex_ai_index_endpoint (endpoint creation, PSC config fields like private_service_connect_config): https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/vertex_ai_index_endpoint
Terraform: google_vertex_ai_index_endpoint_deployed_index (deploying indexes to endpoint, replicas, etc.): https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/vertex_ai_index_endpoint_deployed_index
Terraform: google_vertex_ai_index data source (for lookups/updates): https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/google_vertex_ai_index
RAG infrastructure reference architecture using Vertex AI + Vector Search: https://cloud.google.com/architecture/gen-ai-rag-vertex-ai-vector-search
Vector Search pricing and calculator (for cost modeling): https://cloud.google.com/vertex-ai/pricing#vectorsearch

Next Steps for Automation Team
1. Terraform module: Create Index → Index Endpoint (PSC enabled + CMEK + allowlist) → Deployed Index.
2. Return PSC IP and endpoint details to console.
3. Support full CRUD + updates.
4. Parameterize: region (must have pre-created connection policy), project allowlist, CMEK key name.
5. Add pre-checks: policy existence, key existence, quotas.

This gives a secure, private, self-service Vector Search pattern that fits our enterprise constraints perfectly.
