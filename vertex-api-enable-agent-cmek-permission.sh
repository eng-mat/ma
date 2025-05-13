#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Input parameters
SERVICE_PROJECT_ID="$1"
ENVIRONMENT="$2"  # 'prod' or 'nonprod'

if [[ -z "$SERVICE_PROJECT_ID" || -z "$ENVIRONMENT" ]]; then
  echo "Usage: $0 <SERVICE_PROJECT_ID> <ENVIRONMENT (prod|nonprod)>"
  exit 1
fi

# Validate environment
if [[ "$ENVIRONMENT" != "prod" && "$ENVIRONMENT" != "nonprod" ]]; then
  echo "Environment must be 'prod' or 'nonprod'"
  exit 1
fi

# Vault project ID
VAULT_PROJECT_ID="my-vault-$ENVIRONMENT"

# List of APIs to enable
APIS=(
  dataflow.googleapis.com
  dataform.googleapis.com
  aiplatform.googleapis.com
  notebooks.googleapis.com
  dataproc.googleapis.com
  composer.googleapis.com
  serviceusage.googleapis.com
  generativelanguage.googleapis.com
  dialogflow.googleapis.com
  discoveryengine.googleapis.com
  dlp.googleapis.com
)

# List of locations
LOCATIONS=(
  us-west3
  us-central2
  us-central1
  us
  us-east2
)

# Enable APIs in the service project
echo "Enabling APIs in project: $SERVICE_PROJECT_ID"
for api in "${APIS[@]}"; do
  echo "Enabling API: $api"
  gcloud services enable "$api" --project="$SERVICE_PROJECT_ID"
done

# Retrieve the service project number
SERVICE_PROJECT_NUMBER=$(gcloud projects describe "$SERVICE_PROJECT_ID" --format="value(projectNumber)")

# Assign roles to service agents for each CMEK key
for location in "${LOCATIONS[@]}"; do
  KEY_RING="key-$location"
  KEY_NAME="key-${SERVICE_PROJECT_ID}-${location}"

  # Construct the full resource name
  RESOURCE="projects/$VAULT_PROJECT_ID/locations/$location/keyRings/$KEY_RING/cryptoKeys/$KEY_NAME"

  # List of service agents to grant access
  SERVICE_AGENTS=(
    "service-$SERVICE_PROJECT_NUMBER@dataflow-service-producer-prod.iam.gserviceaccount.com"
    "service-$SERVICE_PROJECT_NUMBER@gcp-sa-dataform.iam.gserviceaccount.com"
    "service-$SERVICE_PROJECT_NUMBER@gcp-sa-aiplatform.iam.gserviceaccount.com"
    "service-$SERVICE_PROJECT_NUMBER@gcp-sa-notebooks.iam.gserviceaccount.com"
    "service-$SERVICE_PROJECT_NUMBER@dataproc-accounts.iam.gserviceaccount.com"
    "service-$SERVICE_PROJECT_NUMBER@composer-accounts.iam.gserviceaccount.com"
    "service-$SERVICE_PROJECT_NUMBER@gcp-sa-serviceusage.iam.gserviceaccount.com"
    "service-$SERVICE_PROJECT_NUMBER@gcp-sa-generativelanguage.iam.gserviceaccount.com"
    "service-$SERVICE_PROJECT_NUMBER@gcp-sa-dialogflow.iam.gserviceaccount.com"
    "service-$SERVICE_PROJECT_NUMBER@gcp-sa-discoveryengine.iam.gserviceaccount.com"
    "service-$SERVICE_PROJECT_NUMBER@gcp-sa-dlp.iam.gserviceaccount.com"
  )

  for agent in "${SERVICE_AGENTS[@]}"; do
    echo "Granting roles/cloudkms.cryptoKeyEncrypterDecrypter to $agent on $RESOURCE"
    gcloud kms keys add-iam-policy-binding "$KEY_NAME" \
      --keyring="$KEY_RING" \
      --location="$location" \
      --project="$VAULT_PROJECT_ID" \
      --member="serviceAccount:$agent" \
      --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
  done
done
