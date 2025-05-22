#!/bin/bash

# This script calculates derived variables and deploys a GCS bucket and Vertex AI Notebook.
# It can operate in dry-run mode or apply mode based on the first argument.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Script Arguments ---
MODE="$1" # Expected: "--dry-run" or "--apply"

# Trim whitespace/hidden characters from MODE
MODE=$(echo "$MODE" | xargs)

# DEBUG: Print the argument received and the MODE variable
echo "DEBUG: Argument 1 received: '$1'"
echo "DEBUG: MODE variable set to: '$MODE'"

# --- Required Environment Variables (passed from GitHub Actions) ---
# SERVICE_PROJECT_ID
# ENVIRONMENT_TYPE (new input: nonprod or prod)
# REGION
# VPC_NAME
# SUBNET_NAME
# INSTANCE_OWNER_EMAIL
# LAST_NAME_FIRST_INITIAL
# MACHINE_TYPE (optional, defaults to e2-standard-4 if not set)

# Validate required environment variables
if [ -z "$SERVICE_PROJECT_ID" ] || \
   [ -z "$ENVIRONMENT_TYPE" ] || \
   [ -z "$REGION" ] || \
   [ -z "$VPC_NAME" ] || \
   [ -z "$SUBNET_NAME" ] || \
   [ -z "$INSTANCE_OWNER_EMAIL" ] || \
   [ -z "$LAST_NAME_FIRST_INITIAL" ]; then
  echo "Error: One or more required environment variables are not set."
  echo "Required: SERVICE_PROJECT_ID, ENVIRONMENT_TYPE, REGION, VPC_NAME, SUBNET_NAME, INSTANCE_OWNER_EMAIL, LAST_NAME_FIRST_INITIAL"
  exit 1
fi

# Set default for MACHINE_TYPE if not provided
if [ -z "$MACHINE_TYPE" ]; then
  MACHINE_TYPE="e2-standard-4"
fi

echo "--- Inputs Received ---"
echo "SERVICE_PROJECT_ID: $SERVICE_PROJECT_ID"
echo "ENVIRONMENT_TYPE: $ENVIRONMENT_TYPE"
echo "REGION: $REGION"
echo "VPC_NAME: $VPC_NAME"
echo "SUBNET_NAME: $SUBNET_NAME"
echo "INSTANCE_OWNER_EMAIL: $INSTANCE_OWNER_EMAIL"
echo "LAST_NAME_FIRST_INITIAL: $LAST_NAME_FIRST_INITIAL"
echo "MACHINE_TYPE: $MACHINE_TYPE"
echo "MODE: $MODE"
echo "-----------------------"

# --- Input Format Validations ---
# Validate SERVICE_PROJECT_ID format (e.g., test-poc-mymy, another-ppoc-project)
# Allows alphanumeric and hyphens, with poc/ppoc specifically in the second segment.
if ! [[ "$SERVICE_PROJECT_ID" =~ ^[a-z0-9-]+-(poc|ppoc)-[a-z0-9.-]+$ ]]; then
  echo "Error: SERVICE_PROJECT_ID '$SERVICE_PROJECT_ID' does not follow the expected format (e.g., test-poc-my-project)."
  exit 1
fi

# Validate INSTANCE_OWNER_EMAIL format
if ! [[ "$INSTANCE_OWNER_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "Error: INSTANCE_OWNER_EMAIL '$INSTANCE_OWNER_EMAIL' is not a valid email address format."
  exit 1
fi

# Validate LAST_NAME_FIRST_INITIAL format (e.g., smith-j)
if ! [[ "$LAST_NAME_FIRST_INITIAL" =~ ^[a-z]+-[a-z]$ ]]; then
  echo "Error: LAST_NAME_FIRST_INITIAL '$LAST_NAME_FIRST_INITIAL' does not follow the expected format (e.g., smith-j)."
  exit 1
fi

# --- Determine Host Project ID based on VPC name mapping ---
# This uses a direct mapping from the selected VPC_NAME to the Host Project ID.
HOST_PROJECT_ID=""
case "$VPC_NAME" in
  "vpc-ss-tru-nonprod-7"|"vpc-ss-tru-prod-7")
    HOST_PROJECT_ID="akilapa-vpc"
    ;;
  "vpc-jjk-tru-nonprod-7"|"vpc-jjk-tru-prod-7")
    HOST_PROJECT_ID="vpc-elese-aki"
    ;;
  "vpc-jjkkula-tru-nonprod-7"|"vpc-jjkkula-tru-prod-7")
    HOST_PROJECT_ID="aya-kudelo-pak"
    ;;
  *)
    echo "Error: Could not determine host project for VPC name '$VPC_NAME'. Please check VPC name selection."
    exit 1
    ;;
esac
echo "Determined Host Project ID: $HOST_PROJECT_ID"

# --- Construct full network and subnet resource paths ---
FULL_NETWORK="projects/${HOST_PROJECT_ID}/global/networks/${VPC_NAME}"
SUBNET_RESOURCE="projects/${HOST_PROJECT_ID}/regions/${REGION}/subnetworks/${SUBNET_NAME}"
echo "Full Network Path: $FULL_NETWORK"
echo "Subnet Resource Path: $SUBNET_RESOURCE"

# --- Determine Vertex AI Notebook Zone ---
# Zone is always region-a
ZONE="${REGION}-a"
echo "Vertex AI Notebook Zone: $ZONE"

# --- Construct Vertex AI Notebook Name ---
# Format: lastname-firstinitial-notebook
NOTEBOOK_NAME="${LAST_NAME_FIRST_INITIAL}-notebook"
echo "Vertex AI Notebook Name: $NOTEBOOK_NAME"

# --- Construct Vertex AI Service Account Email ---
# Format: vertexai-sa@${SERVICE_PROJECT_ID}.iam.gserviceaccount.com
VERTEX_SA="vertexai-sa@${SERVICE_PROJECT_ID}.iam.gserviceaccount.com"
echo "Vertex AI Service Account: $VERTEX_SA"

# --- Construct CMEK Key for Notebook and GCS Bucket ---
# Format: projects/my-key-(nonprod or prod)/locations/(us-east4 or us-central1)/keyRings/key-(nonprod or prod)-(us-east4 or us-central1)-my-(project_id)-(us-east4 or us-central1)
CMEK_VAULT_PROJECT="my-key-${ENVIRONMENT_TYPE}" # Uses the ENVIRONMENT_TYPE input
CMEK_KEY_LOCATION="${REGION}"
CMEK_KEY_RING="key-${ENVIRONMENT_TYPE}-${REGION}-my-${SERVICE_PROJECT_ID}-${REGION}" # Uses the ENVIRONMENT_TYPE input
CMEK_KEY="projects/${CMEK_VAULT_PROJECT}/locations/${CMEK_KEY_LOCATION}/keyRings/${CMEK_KEY_RING}/cryptoKeys/key-${ENVIRONMENT_TYPE}-${REGION}-my-${SERVICE_PROJECT_ID}-${REGION}"
echo "CMEK Key: $CMEK_KEY"

# --- Construct GCS Bucket Name and its CMEK Key ---
# Bucket name: vertex-gcs-${project_id}
GCS_BUCKET_NAME="vertex-gcs-${SERVICE_PROJECT_ID}"
# GCS bucket uses the same CMEK key as the notebook.
GCS_CMEK_KEY="${CMEK_KEY}"
echo "GCS Bucket Name: $GCS_BUCKET_NAME"
echo "GCS Bucket CMEK Key: $GCS_CMEK_KEY"

# --- Execute gcloud commands based on MODE ---
if [ "$MODE" == "--dry-run" ]; then
  echo "--- Performing Dry Run for GCS Bucket Creation ---"
  # Check if GCS bucket already exists before dry-running creation
  if ! gcloud storage buckets describe "gs://${GCS_BUCKET_NAME}" --project="${SERVICE_PROJECT_ID}" &> /dev/null; then
    echo "GCS bucket 'gs://${GCS_BUCKET_NAME}' not found. Simulating creation."
    # For dry-run of creation commands, it's safest to just echo the command.
    echo "Simulating: gcloud storage buckets create \"gs://${GCS_BUCKET_NAME}\" --project=\"${SERVICE_PROJECT_ID}\" --location=\"${REGION}\" --default-kms-key=\"${GCS_CMEK_KEY}\" --uniform-bucket-level-access"
  else
    echo "GCS bucket 'gs://${GCS_BUCKET_NAME}' already exists. Skipping dry run for creation as it already exists."
  fi

  echo "--- Performing Dry Run for Vertex AI Notebook Creation ---"
  # Check if Vertex AI Notebook instance already exists before dry-running creation
  if ! gcloud workbench instances describe "${NOTEBOOK_NAME}" --project="${SERVICE_PROJECT_ID}" --location="${ZONE}" &> /dev/null; then
    echo "Vertex AI Notebook instance '${NOTEBOOK_NAME}' not found in zone '${ZONE}'. Simulating creation."
    # For dry-run of creation commands, it's safest to just echo the command.
    echo "Simulating: gcloud workbench instances create \"${NOTEBOOK_NAME}\" --project=\"${SERVICE_PROJECT_ID}\" --location=\"${ZONE}\" --machine-type=\"${MACHINE_TYPE}\" --boot-disk-size=150GB --data-disk-size=100GB --subnet=\"${SUBNET_RESOURCE}\" --network=\"${FULL_NETWORK}\" --service-account=\"${VERTEX_SA}\" --no-enable-public-ip --no-enable-realtime-in-terminal --owner=\"${INSTANCE_OWNER_EMAIL}\" --enable-notebook-upgrade-scheduling --notebook-upgrade-schedule=\"WEEKLY:SATURDAY:21:00\" --metadata=jupyter_notebook_version=JUPYTER_4_PREVIEW --kms-key=\"${CMEK_KEY}\" --no-shielded-secure-boot --shielded-integrity-monitoring --shielded-vtpm"
  else
    echo "Vertex AI Notebook instance '${NOTEBOOK_NAME}' already exists in zone '${ZONE}'. Skipping dry run for creation as it already exists."
  fi

elif [ "$MODE" == "--apply" ]; then
  echo "--- Applying GCS Bucket Creation ---"
  # Check if GCS bucket already exists before applying creation
  if ! gcloud storage buckets describe "gs://${GCS_BUCKET_NAME}" --project="${SERVICE_PROJECT_ID}" &> /dev/null; then
    echo "GCS bucket 'gs://${GCS_BUCKET_NAME}' not found. Proceeding with creation."
    echo "Executing GCS bucket creation command: gcloud storage buckets create \"gs://${GCS_BUCKET_NAME}\" --project=\"${SERVICE_PROJECT_ID}\" --location=\"${REGION}\" --default-kms-key=\"${GCS_CMEK_KEY}\" --uniform-bucket-level-access"
    gcloud storage buckets create "gs://${GCS_BUCKET_NAME}" \
      --project="${SERVICE_PROJECT_ID}" \
      --location="${REGION}" \
      --default-kms-key="${GCS_CMEK_KEY}" \
      --uniform-bucket-level-access
  else
    echo "GCS bucket 'gs://${GCS_BUCKET_NAME}' already exists. Skipping creation."
  fi

  echo "--- Applying Vertex AI Notebook Creation ---"
  # Check if Vertex AI Notebook instance already exists before applying creation
  if ! gcloud workbench instances describe "${NOTEBOOK_NAME}" --project="${SERVICE_PROJECT_ID}" --location="${ZONE}" &> /dev/null; then
    echo "Vertex AI Notebook instance '${NOTEBOOK_NAME}' not found in zone '${ZONE}'. Proceeding with creation."
    echo "Executing Vertex AI Notebook creation command: gcloud workbench instances create \"${NOTEBOOK_NAME}\" --project=\"${SERVICE_PROJECT_ID}\" --location=\"${ZONE}\" --machine-type=\"${MACHINE_TYPE}\" --boot-disk-size=150GB --data-disk-size=100GB --subnet=\"${SUBNET_RESOURCE}\" --network=\"${FULL_NETWORK}\" --service-account=\"${VERTEX_SA}\" --no-enable-public-ip --no-enable-realtime-in-terminal --owner=\"${INSTANCE_OWNER_EMAIL}\" --enable-notebook-upgrade-scheduling --notebook-upgrade-schedule="WEEKLY:SATURDAY:21:00" --metadata=jupyter_notebook_version=JUPYTER_4_PREVIEW --kms-key=\"${CMEK_KEY}\" --no-shielded-secure-boot --shielded-integrity-monitoring --shielded-vtpm"
    gcloud workbench instances create "${NOTEBOOK_NAME}" \
      --project="${SERVICE_PROJECT_ID}" \
      --location="${ZONE}" \
      --machine-type="${MACHINE_TYPE}" \
      --boot-disk-size=150GB \
      --data-disk-size=100GB \
      --subnet="${SUBNET_RESOURCE}" \
      --network="${FULL_NETWORK}" \
      --service-account="${VERTEX_SA}" \
      --no-enable-public-ip \
      --no-enable-realtime-in-terminal \
      --owner="${INSTANCE_OWNER_EMAIL}" \
      --enable-notebook-upgrade-scheduling \
      --notebook-upgrade-schedule="WEEKLY:SATURDAY:21:00" \
      --metadata=jupyter_notebook_version=JUPYTER_4_PREVIEW \
      --kms-key="${CMEK_KEY}" \
      --no-shielded-secure-boot \
      --shielded-integrity-monitoring \
      --shielded-vtpm
  else
    echo "Vertex AI Notebook instance '${NOTEBOOK_NAME}' already exists in zone '${ZONE}'. Skipping creation."
  fi

else
  echo "Error: Invalid mode. Use '--dry-run' or '--apply'."
  exit 1
fi

echo "Script execution complete."
