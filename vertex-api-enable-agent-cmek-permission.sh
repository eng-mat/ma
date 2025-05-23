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

# APIs that ONLY need to be enabled.  No further processing.
ONLY_ENABLE_APIS=(
  serviceusage.googleapis.com
  generativelanguage.googleapis.com
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

# Mapping of APIs to their corresponding service agents
declare -A SERVICE_AGENTS=(
  [dataflow.googleapis.com]="service-PROJECT_NUMBER@dataflow-service-producer-prod.iam.gserviceaccount.com"
  [dataform.googleapis.com]="service-PROJECT_NUMBER@gcp-sa-dataform.iam.gserviceaccount.com"
  [aiplatform.googleapis.com]="service-PROJECT_NUMBER@gcp-sa-aiplatform.iam.gserviceaccount.com"
  [notebooks.googleapis.com]="service-PROJECT_NUMBER@gcp-sa-notebooks.iam.gserviceaccount.com"
  [dataproc.googleapis.com]="service-PROJECT_NUMBER@dataproc-accounts.iam.gserviceaccount.com"
  [composer.googleapis.com]="service-PROJECT_NUMBER@composer-accounts.iam.gserviceaccount.com"
  [dialogflow.googleapis.com]="service-PROJECT_NUMBER@gcp-sa-dialogflow.iam.gserviceaccount.com"
  [discoveryengine.googleapis.com]="service-PROJECT_NUMBER@gcp-sa-discoveryengine.iam.gserviceaccount.com"
  [dlp.googleapis.com]="service-PROJECT_NUMBER@gcp-sa-dlp.iam.gserviceaccount.com"
)

# Trigger service agent creation and assign roles for the remaining APIs
for api in "${APIS[@]}"; do
  # Check if the current API is in the list that only needs enabling
  if ! contains "${ONLY_ENABLE_APIS[@]}" "$api"; then
    echo "Processing API: $api (Agent creation and role assignment)"
    # Trigger service agent creation
    echo "Triggering service agent creation for API: $api"
    gcloud beta services identity create --service="$api" --project="$SERVICE_PROJECT_ID" || true

    # Wait for service agents to become available
    echo "Waiting for service agent to become available..."
    sleep 7
  fi
done

# Assign roles to service agents for each CMEK key
for location in "${LOCATIONS[@]}"; do
  KEY_RING="key-$location"
  KEY_NAME="key-${SERVICE_PROJECT_ID}-${location}"

  for api in "${APIS[@]}"; do
     if ! contains "${ONLY_ENABLE_APIS[@]}" "$api"; then
      agent_template="${SERVICE_AGENTS[$api]}"
      agent_email="${agent_template/PROJECT_NUMBER/$SERVICE_PROJECT_NUMBER}"

      echo "Granting roles/cloudkms.cryptoKeyEncrypterDecrypter to $agent_email on key $KEY_NAME in $location"
      gcloud kms keys add-iam-policy-binding "$KEY_NAME" \
        --keyring="$KEY_RING" \
        --location="$location" \
        --project="$VAULT_PROJECT_ID" \
        --member="serviceAccount:$agent_email" \
        --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
    fi
  done
done

# Helper function to check if an element exists in an array
contains() {
  local element="$1"
  shift
  local array=("$@")

  for item in "${array[@]}"; do
    if [[ "$item" = "$element" ]]; then
      return 0 # Found
    fi
  done
  return 1 # Not found
}
