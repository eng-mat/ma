# CDE Platform — Final Architecture (end-to-end spec)

Text-only specification (no diagram needed). Internal-only, agent-assisted platform on
Google Cloud. Two environments: **dev** and **prod**. Runs in a **Shared VPC** where the
networking already exists.

## 1. Overview
Users reach an internal web app; a backend serves APIs and does data work; a managed AI
agent (Vertex AI Agent Engine, built with ADK) handles reasoning and grounded generation.
All ingress is internal (no public endpoints).

## 2. Components to build

**Compute / app (Cloud Run)**
- **Frontend** — Cloud Run **Service** (web UI). Internal ingress only. Sits behind an
  **internal** Application Load Balancer with **IAP**; reached on a **custom domain via
  private DNS**.
- **Backend** — Cloud Run **Service** (APIs). Internal ingress. Called **directly** by the
  frontend (service-to-service) and by the agent. Talks to Firestore, BigQuery, and the
  external systems over REST.
- **Data Connector** — Cloud Run **function or Job** (ingestion). Pulls from **BigQuery,
  Alation, SharePoint, and Excel**, writes into the BigQuery working dataset. Scheduled
  batch → Cloud Run **Job** (Cloud Scheduler); on-demand → function/service.

**AI**
- **Agent Engine** — **managed Vertex AI Agent Engine (Reasoning Engine), built with ADK**.
  The L2 orchestrator agent. Uses **Gemini** for reasoning and **Vertex AI Search** for RAG
  grounding. Managed **sessions/memory**. Calls external systems over REST and reads/writes
  BigQuery. Runs as its own runtime SA.
- **Vertex AI Search** — a **data store** (grounding corpus) the agent queries.
- **Model Armor** — project **floor setting + template**; **prompt inspection and
  response/tool inspection** on the agent.

**Data**
- **BigQuery** — a platform-owned **working dataset** (`cde_working`, agent memory +
  ingestion target) and **existing source datasets** (read-only).
- **Firestore** — Native mode, for app/UI state. (Agent sessions/memory are handled by
  Agent Engine, so Firestore is only for app-side state.)
- **Cloud Storage** — a **staging bucket** for Agent Engine deploys; buckets for
  artifacts/Excel source files.

**Security / platform / observability**
- **Secret Manager** — external-API credentials (Alation, SharePoint, MS Graph).
- **Cloud DLP (Sensitive Data Protection)** — **redacts PII** from logs/telemetry/chat
  history before storage.
- **Observability** — Cloud **Logging / Monitoring / Trace**, with logs **exported to
  Dynatrace**.
- **Artifact Registry** — Docker repo receiving images promoted from JFrog.
- **KMS** — CMEK (optional).
- **Cloud Scheduler** — triggers the scheduled agentic run / connector / notifications.

**Explicitly removed:** no MCP servers (the agent/backend call external APIs directly over
REST); **no external load balancer** (everything internal).

## 3. Networking — Shared VPC (already established)
- **Host project owns** (exists; we reference): the VPC network, subnets, **proxy-only
  subnet** (`REGIONAL_MANAGED_PROXY`), the **Serverless VPC connector**, **Cloud NAT + a
  reserved static egress IP**, **private DNS**, and firewalls.
- **Service project owns** (we create): all workloads **plus the internal LB resources**,
  which **reference the host subnets**.
- **Egress:** Cloud Run reaches internal resources and Google APIs privately (**Private
  Google Access**); external SaaS (SharePoint/Outlook/Alation) egress goes out through
  **Cloud NAT** using the **static IP** those systems allow-list.
- **No VPC peering / no PSA.** Use **PSC** where a private path to a managed service is needed.
- **Key host→service grant:** `roles/compute.networkUser` on the specific subnet(s) to the
  service project's **Cloud Run service agent** and **Google APIs service agent**.

## 4. Ingress & identity
- **Internal Application Load Balancer** (regional, `INTERNAL_MANAGED`) fronts the
  **frontend** only. Pieces: internal **VIP** on the app subnet → **forwarding rule (443)**
  → **target HTTPS proxy** (regional SSL cert from the internal CA) → **URL map** →
  **backend service** (`INTERNAL_MANAGED`, HTTPS) → **serverless NEG** → frontend Cloud Run.
- **IAP** enabled on that LB backend service. Identity is **Okta via Workforce Identity
  Federation**; only members of an **allow-group** (`roles/iap.httpsResourceAccessor`) get
  in. Internal users only.
- **The backend is NOT behind the LB** — the frontend calls it directly, and the frontend SA
  holds `roles/run.invoker` on the backend.
- **Separate service accounts per component** (frontend, backend, data-connector,
  agent-runtime, deploy) — least privilege.

## 5. Service accounts & key IAM
- **frontend SA:** `run.invoker` on backend; `secretmanager.secretAccessor` if needed.
- **backend SA:** `datastore.user` (Firestore); `bigquery.dataEditor` + `bigquery.jobUser`;
  `secretmanager.secretAccessor`.
- **data-connector SA:** `bigquery.dataEditor` + `jobUser`; `bigquery.dataViewer` (source
  datasets); `secretmanager.secretAccessor`; `storage.objectViewer` (Excel).
- **agent-runtime SA:** `aiplatform.user`; `discoveryengine.editor`;
  `secretmanager.secretAccessor`; `bigquery.dataViewer` (+ editor if it writes);
  `storage.objectAdmin` (staging bucket); `logging.logWriter`.
- **deploy SA (CI):** `run.admin`; `iam.serviceAccountUser` (act as runtime SAs);
  `artifactregistry.writer/reader`; for agents also `aiplatform.user` + staging-bucket access.
- **Cloud Run service agent:** `artifactregistry.reader` (pull images).

## 6. Repositories (4)
- **frontend** (Cloud Run image)
- **backend** (Cloud Run image)
- **agents** (ADK agent → Agent Engine; **package, not image**)
- **infrastructure** (central Terraform repo; provisions the "shells" and all resources above)

## 7. CI/CD & deployment model

**Two-layer model:**
- **Terraform (infra repo, once):** creates the **shells** — Cloud Run services (placeholder
  image), the Agent Engine (placeholder agent), and all supporting resources — with
  **`ignore_changes` on the running image/agent**, so app deploys are never reverted.
- **App pipelines (per push, human-triggered):** deploy the **real code** into those shells.

**Cloud Run repos (frontend, backend, data-connector):**
1. Push to `dev` → **auto**: scan + build **container image** → push to **JFrog**.
2. **Manual** pipeline: promote image **JFrog → Artifact Registry** → **`gcloud run deploy`**
   a new revision into the existing service. First deploy done together; thereafter routine.
3. Deploy to **dev** then **prod** (manual approval), same image promoted.

**Agents repo (ADK + Agent Engine) — no container:**
1. Push to `dev` → **auto**: unit tests + **`adk eval`** (quality/hallucination gate) →
   **package the agent** (wheel/tarball) → push to a **JFrog PyPI/generic repo**.
2. **Manual** deploy: pull the package →
   **`adk deploy agent_engine --agent_engine_id <ID> --staging_bucket gs://…`** — uploads to
   the **staging bucket** and **updates the existing engine in place**.
3. **Critical rule:** always target the **existing engine's ID** — never run `adk deploy`
   without an id, or it creates duplicate engines.
4. **Engine ownership (pick one):** Terraform creates the engine shell and ADK updates it by
   id (consistent with Cloud Run), **or** Terraform provisions only the runtime SA + staging
   bucket + IAM and **ADK owns the engine** (first deploy creates it, later deploys update).

**Auth:** all pipelines authenticate **keyless via Workload Identity Federation** to the
environment's deploy SA. No service-account keys.

## 8. Artifacts in JFrog
- **3 Docker images** — frontend, backend, data-connector (→ Artifact Registry → Cloud Run).
- **1 Python/generic package** — the ADK agent (→ `adk deploy agent_engine`, not AR).
- Set up **two JFrog repo types**: a **Docker** repo and a **PyPI/generic** repo.

## 9. End-to-end runtime flow
1. **Internal user** (Okta allow-group) → HTTPS on the **custom domain** (private DNS) →
   **internal LB** → **IAP** (Okta auth) → **frontend Cloud Run**.
2. **Frontend → backend** (direct internal call, `run.invoker`).
3. **Backend** → Firestore (app state), BigQuery (data), and **external REST**
   (SharePoint/Outlook/Alation) via the connector + **Cloud NAT**.
4. **Backend / Cloud Scheduler** triggers the **Agent Engine** orchestrator.
5. **Agent Engine (ADK, Gemini)** → **Vertex AI Search** (grounding), **BigQuery** (memory),
   **external REST** via NAT; **Model Armor** inspects prompts and responses.
6. **Data Connector** (scheduled or on-demand) pulls **BigQuery / Alation / SharePoint /
   Excel** → writes the BigQuery **working dataset**.
7. **Logs, telemetry, chat history** → **Cloud DLP** redacts PII →
   **Cloud Logging/Monitoring/Trace** → exported to **Dynatrace**.

## 10. Build checklist
**Service project:** enable APIs (`run, cloudfunctions, iam, firestore, bigquery,
secretmanager, artifactregistry, aiplatform, discoveryengine, modelarmor, vpcaccess, iap,
compute, cloudkms, logging, monitoring`); create per-component **SAs**; **Cloud Run**
frontend/backend/data-connector; **Agent Engine** shell + **staging bucket**; **Vertex AI
Search** data store; **Model Armor** floor + template; **Firestore**; **BigQuery** working
dataset + source read; **Secret Manager** secrets; **Artifact Registry**; **internal LB**
(VIP, forwarding rule, target HTTPS proxy, cert, URL map, backend service, serverless NEG) +
**IAP**; **Cloud DLP** config; **log export to Dynatrace**; **Cloud Scheduler** jobs.

**Host project (request only):** subnet self-links, connector name, proxy-only subnet, Cloud
NAT + static IP, **private DNS record** (domain → LB VIP), **firewall** (proxy range → Cloud
Run), **`compute.networkUser`** grant. Host APIs: `compute, dns, vpcaccess, networkconnectivity`.

**Repos + CI/CD:** frontend/backend/data-connector (image → JFrog → AR → Cloud Run); agents
(ADK package → JFrog → `adk deploy agent_engine`); infra Terraform creates shells; WIF everywhere.
