# CDE Platform — Customer Provisioning Requirements

What the customer needs to **create / grant** in each GCP project so the CDE services can
be deployed and run. Everything is **internal-only**. Two environments: **dev** and **prod**
(repeat the whole list per project). Fill in the `<...>` values with your standards.

---

## 0. Image flow (matches your CI/CD)

```
app code → dev branch → (auto) scan + build + push image → JFrog Artifactory
                          → (manual pipeline) promote image: JFrog → Artifact Registry
                          → deploy Cloud Run service (image + region), first time WITH us
                          → thereafter: push to dev → build → JFrog → (manual) → AR → deploy
```

So the customer must provide: an **Artifact Registry** repo to receive promoted images, a
**promotion/deploy identity** with rights to push to AR and deploy Cloud Run, and the
Cloud Run **runtime service accounts** below.

---

## 1. APIs to enable (per project)

`run.googleapis.com`, `cloudfunctions.googleapis.com`, `iam.googleapis.com`,
`firestore.googleapis.com`, `bigquery.googleapis.com`, `secretmanager.googleapis.com`,
`artifactregistry.googleapis.com`, `aiplatform.googleapis.com`,
`discoveryengine.googleapis.com`, `modelarmor.googleapis.com`, `compute.googleapis.com`,
`vpcaccess.googleapis.com`, `iap.googleapis.com`, `dns.googleapis.com`,
`cloudkms.googleapis.com`, `logging.googleapis.com`, `monitoring.googleapis.com`.

---

## 2. Service accounts + IAM (the core of the request)

Create one **runtime service account per service**, plus one **deploy/promotion** identity.
Grant least privilege:

| Service account | Grant (roles) | On |
|---|---|---|
| **frontend** run SA | `roles/secretmanager.secretAccessor` (if it reads secrets) | project |
| **backend** run SA | `roles/datastore.user` (Firestore), `roles/bigquery.dataEditor` + `roles/bigquery.jobUser`, `roles/secretmanager.secretAccessor` | project |
| **data-connector** function SA | `roles/bigquery.dataEditor` + `roles/bigquery.jobUser`, `roles/bigquery.dataViewer` (on source datasets), `roles/secretmanager.secretAccessor`, `roles/storage.objectViewer` (Excel files in GCS) | project / source datasets |
| **agent-runtime** SA (Agent Engine) | `roles/aiplatform.user`, `roles/discoveryengine.editor`, `roles/secretmanager.secretAccessor`, `roles/datastore.user`, `roles/bigquery.dataViewer`, `roles/logging.logWriter` | project |
| **deploy/promotion** SA (your pipeline) | `roles/run.admin` (deploy), `roles/iam.serviceAccountUser` (act as the runtime SAs), `roles/artifactregistry.writer` + `roles/artifactregistry.reader` | project / AR repo |
| **Cloud Run service agent** `service-<projNum>@serverless-robot-prod.iam.gserviceaccount.com` | `roles/artifactregistry.reader` (to pull the image) | AR repo |

> Rule: a service's runtime SA holds **only** what that service touches. The deploy SA can
> *act as* the runtime SAs but is separate from them.

---

## 3. Cloud Run services — what to create + parameters

Create these services (deploy the first revision **with us**; image comes from AR):

**frontend**, **backend** (and the **data-connector** in §4).

| Parameter | Value |
|---|---|
| Region | `<us-central1>` |
| Image | `<region>-docker.pkg.dev/<project>/<repo>/<service>:<tag>` (from AR) |
| Service account | the service's runtime SA (§2) |
| Ingress | **`internal`** (internal + Cloud Load Balancing only) — **no public ingress** |
| Execution environment | gen2 |
| CPU / Memory | `<1 vCPU>` / `<512Mi–1Gi>` |
| Concurrency | `<80>` |
| Min / Max instances | `<0>` / `<4>` |
| Port | `8080` |
| VPC egress | Serverless VPC connector (or Direct VPC egress); egress `PRIVATE_RANGES_ONLY` (or `ALL_TRAFFIC` if going out via NAT) |
| Env vars | `<per service>` |
| Secrets (mounted/env) | `<from Secret Manager, §5>` |
| Deletion protection | on (prod) |

---

## 4. Data Connector — Cloud Run function (NEW)

A Cloud Run **function** (gen2) that pulls data from **BigQuery, Alation, SharePoint, and
Excel**, and writes into the CDE working dataset.

| Parameter | Value |
|---|---|
| Trigger | HTTP (called by backend / Cloud Scheduler) — internal ingress |
| Runtime SA | **data-connector** SA (§2) |
| Ingress | internal only |
| VPC egress | connector; egress `ALL_TRAFFIC` (needs to reach external Alation/SharePoint) |
| Needs | BigQuery read/write, Secret Manager (Alation + SharePoint/MS Graph creds), Storage read (Excel files), outbound internet **via Cloud NAT** (static egress IP for allow-listing) |

Permissions: see the **data-connector** row in §2.

---

## 5. Firestore — what to create + parameters

| Parameter | Value |
|---|---|
| Type | **Native** |
| Location | `<nam5>` (or a region) |
| Edition | Standard |
| Point-in-time recovery | **enabled** |
| Delete protection | **enabled** (prod) |
| Daily backups | retention `<7 days>` |
| CMEK | optional (`<KMS key>`) |

**Access:** grant `roles/datastore.user` to the **backend** and **agent-runtime** SAs.

---

## 6. Secret Manager — secrets + access

Create these **secret containers** (values added out-of-band; never in code):
`alation-api-token`, `sharepoint-client-secret`, `msgraph-client-secret`, plus any Excel/
source-system credentials.

| Parameter | Value |
|---|---|
| Replication | automatic (or user-managed, pinned to `<region>`) |
| CMEK | optional |

**Access:** grant `roles/secretmanager.secretAccessor` to the SA that reads each secret
(data-connector and/or backend), scoped per secret.

---

## 7. BigQuery — datasets + access

- **Create** the platform-owned dataset: `cde_working` (location `<US>`) — CDE working set +
  agent memory.
- **Existing source datasets** (already populated): grant **read** to the data-connector and
  agent SAs.

| Grant | Role | On |
|---|---|---|
| data-connector, agent SAs | `roles/bigquery.dataViewer` | source datasets |
| data-connector, backend SAs | `roles/bigquery.dataEditor` | `cde_working` |
| data-connector, backend SAs | `roles/bigquery.jobUser` | project |

---

## 8. Artifact Registry

| Parameter | Value |
|---|---|
| Format | Docker |
| Repo id / region | `<cde-images>` / `<us-central1>` |
| Immutable tags | recommended (commit-SHA tags) |
| CMEK | optional |

**Access:** deploy/promotion SA `roles/artifactregistry.writer`; Cloud Run service agent
`roles/artifactregistry.reader`.

---

## 9. Vertex AI

- **Agent Engine** (Reasoning Engine): region `<us-central1>`, runs as the **agent-runtime** SA.
- **Vertex AI Search**: a data store (+ search app) for RAG grounding.
- **Model Armor** (if in scope): project floor setting + templates (prompt + response
  inspection) integrated with AI Platform.

---

## 10. Networking — everything internal

| Item | Detail |
|---|---|
| **Internal Application LB** (frontend) | Regional `INTERNAL_MANAGED` HTTPS LB → serverless NEG → frontend Cloud Run. **No external LB.** |
| **Proxy-only subnet** | `REGIONAL_MANAGED_PROXY` in-region (required by the internal LB) |
| **Serverless VPC connector** (or Direct VPC egress) | so Cloud Run reaches internal + (via NAT) external |
| **Cloud NAT + reserved static IP** | egress to Alation / SharePoint / MS Graph (the IP they allow-list) |
| **Private Google Access** | on the subnets, so Google APIs are reached privately (no external IPs) |
| **Private DNS zone** | custom domain (e.g. `cde.internal.<company>.com`) → the internal LB VIP |
| **Regional SSL certificate** | from the internal CA, for HTTPS on the internal LB |
| **Firewall** | allow proxy-subnet → Cloud Run; allow the connector ranges |
| **(If Apigee for egress)** | reach it via **PSC** (no VPC peering / PSA) |
| App subnet | provide the self-link for the LB VIP |

---

## 11. Identity-Aware Proxy (IAP) — access control

| Item | Detail |
|---|---|
| IAP | enabled on the frontend internal LB backend service |
| Identity | **Okta** via Workforce Identity Federation |
| Allow-group | grant `roles/iap.httpsResourceAccessor` to the Okta group (e.g. `group:cde-app-users@<company>.com`) |
| Access | **internal users in the allow-group only** |

---

## 12. Summary of "please create for us"

1. Enable the APIs (§1).
2. Create the **runtime SAs** (frontend, backend, data-connector, agent-runtime) + the
   **deploy/promotion SA**, with the roles in §2.
3. Create the **Artifact Registry** repo + grant push/pull (§8).
4. Create **Firestore** (§5), **Secret Manager** secrets (§6), **BigQuery** `cde_working` +
   source-dataset read (§7).
5. Provision **networking** (§10): internal LB, proxy-only subnet, VPC connector, Cloud NAT
   + static IP, Private Google Access, private DNS, internal SSL cert, firewall.
6. Configure **IAP** + the **Okta allow-group** (§11).
7. Stand up **Agent Engine + Vertex AI Search** (+ Model Armor) (§9).
8. Deploy the **Cloud Run services + data-connector function** first revision **with us**
   (§3, §4), image promoted from JFrog → Artifact Registry.
