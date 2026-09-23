Frontend Cloud Run service
Cloud Run service cde-<env>-frontend, ingress = internal (INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER), gen2, port 8080, image from Artifact Registry.
Frontend runtime SA (separate from backend): run.invoker on the backend service; secretmanager.secretAccessor if it reads secrets.
Internal Application Load Balancer (regional, INTERNAL_MANAGED) — the 3 pieces
Frontend (the ingress):
Internal static IP / VIP on the app subnet
Forwarding rule (INTERNAL_MANAGED, port 443, on the host network + app subnet)
Target HTTPS proxy
Regional SSL certificate (from the internal CA / Certificate Manager)
URL map (router): default → the LB backend service
Backend service (of the LB, INTERNAL_MANAGED, HTTPS):
Serverless NEG → the frontend Cloud Run service
IAP enabled on this backend service
IAP / access
IAP on the LB backend service; Okta via Workforce Identity Federation
Grant roles/iap.httpsResourceAccessor to the Okta allow-group — internal users only
Networking (host-owned, we reference)
App subnet self-link (for the VIP)
Proxy-only subnet (REGIONAL_MANAGED_PROXY) in-region — required by the internal LB
Firewall: allow the proxy-only subnet range → frontend Cloud Run
compute.networkUser on the subnet → service project's Cloud Run service agent + Google APIs service agent
Private DNS record: custom domain → the internal VIP
Custom domain
Internal domain (e.g. cde.<env>.internal.<company>.com)
Private DNS A record → VIP; SSL cert covering that domain