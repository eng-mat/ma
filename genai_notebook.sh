#!/bin/bash

# ========== USER INPUT ==========
read -p "Enter service project ID: " SERVICE_PROJECT
read -p "Enter host project ID: " HOST_PROJECT
read -p "Enter region: " REGION
read -p "Enter zone: " ZONE
read -p "Enter host VPC network name: " HOST_VPC
read -p "Enter subnet name: " SUBNET_NAME
read -p "Enter Workbench instance name: " WORKBENCH_NAME
read -p "Enter CMEK key (e.g., projects/PROJECT_ID/locations/LOCATION/keyRings/KEY_RING/cryptoKeys/KEY): " CMEK_KEY
read -p "Enter machine type (e.g., e2-standard-4): " MACHINE_TYPE
read -p "Enter owner user email: " OWNER_EMAIL
read -p "Enter cloud engineers group email: " CLOUD_ENG_GROUP
read -p "Enter customer group email: " CUSTOMER_GROUP_EMAIL

# ========== DERIVED VARIABLES ==========
SERVICE_ACCOUNT="vertexai@$SERVICE_PROJECT.iam.gserviceaccount.com"
SUBNET_RESOURCE="projects/$HOST_PROJECT/regions/$REGION/subnetworks/$SUBNET_NAME"
FULL_NETWORK="projects/$HOST_PROJECT/global/networks/$HOST_VPC"

# ========== STEP 1: Create Service Account ==========
echo "Creating service account: $SERVICE_ACCOUNT"
gcloud iam service-accounts create vertexai \
  --project="$SERVICE_PROJECT" \
  --display-name="Vertex AI Workbench Service Account"

# ========== STEP 2: Grant subnet access to service account ==========
echo "Granting subnet access to service account"
gcloud compute networks subnets set-iam-policy "$SUBNET_NAME" \
  --region="$REGION" \
  --project="$HOST_PROJECT" \
  <(cat <<EOF
bindings:
- members:
  - serviceAccount:$SERVICE_ACCOUNT
  role: roles/compute.networkUser
etag: ACAB
EOF
)

# ========== STEP 3: Grant subnet access to group emails ==========
echo "Granting subnet access to engineering and customer group emails"
gcloud compute networks subnets set-iam-policy "$SUBNET_NAME" \
  --region="$REGION" \
  --project="$HOST_PROJECT" \
  <(cat <<EOF
bindings:
- members:
  - group:$CLOUD_ENG_GROUP
  - group:$CUSTOMER_GROUP_EMAIL
  role: roles/compute.networkUser
etag: ACAB
EOF
)

# ========== STEP 4: Create Vertex AI Workbench ==========
echo "Creating Vertex AI Workbench instance..."

gcloud beta notebooks instances create "$WORKBENCH_NAME" \
  --project="$SERVICE_PROJECT" \
  --location="$ZONE" \
  --vm-image-project=deeplearning-platform-release \
  --vm-image-family=common-cpu-notebooks \
  --machine-type="$MACHINE_TYPE" \
  --boot-disk-size=150GB \
  --data-disk-size=100GB \
  --subnet="$SUBNET_RESOURCE" \
  --network="$FULL_NETWORK" \
  --service-account="$SERVICE_ACCOUNT" \
  --no-enable-public-ip \
  --no-enable-realtime-in-terminal \
  --owner="$OWNER_EMAIL" \
  --enable-notebook-upgrade-scheduling \
  --notebook-upgrade-schedule="WEEKLY:SATURDAY:21:00" \
  --metadata=jupyter_notebook_version=JUPYTER_4_PREVIEW \
  --kms-key="$CMEK_KEY" \
  --no-shielded-secure-boot \
  --shielded-integrity-monitoring \
  --shielded-vtpm

echo "✅ Vertex AI Workbench instance '$WORKBENCH_NAME' created successfully."
