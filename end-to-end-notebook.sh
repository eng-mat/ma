**1. GitHub Actions Workflow (`.github/workflows/create_vertex_ai_workbench.yaml`):**

```yaml
name: Create Vertex AI Workbench Instance
on:
  workflow_dispatch:
    inputs:
      service_project:
        description: "Service Project ID"
        type: string
        required: true
      host_project:
        description: "Host Project ID (HOST_PROJECT1, HOST_PROJECT2, HOST_PROJECT3)"
        type: string
        required: true
      region:
        description: "Region"
        type: string
        required: true
      zone:
        description: "Zone"
        type: string
        required: true
      host_vpc:
        description: "Host VPC Network Name"
        type: string
        required: true
      subnet_name:
        description: "Subnet Name"
        type: string
        required: true
      workbench_name:
        description: "Workbench Instance Name"
        type: string
        required: true
      cmek_key:
        description: >-
          CMEK key (e.g.,
          projects/PROJECT_ID/locations/LOCATION/keyRings/KEY_RING/cryptoKeys/KEY)
        type: string
        required: true
      machine_type:
        description: "Machine type (e.g., e2-standard-4)"
        type: string
        required: true
      owner_email:
        description: "Owner User Email"
        type: string
        required: true
      cloud_eng_group:
        description: "Cloud Engineers Group Email"
        type: string
        required: true
      customer_group_email:
        description: "Customer Group Email"
        type: string
        required: true

env:
  PROJECT_ID: ${{ github.repository }} # The repository where this workflow is defined.

jobs:
  create-workbench-instance:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up gcloud
        uses: google-github-actions/setup-gcloud@v2
        with:
          service_account_key: ${{ secrets.GCP_SA_KEY }}  # Use the secret
          project_id: ${{ env.PROJECT_ID }}

      - name: Install gcloud components
        run: |
          gcloud components update --quiet
          gcloud components install beta --quiet

      - name: Execute script
        run: |
          chmod +x create_workbench.sh # Make script executable
          ./create_workbench.sh \
          "${{ github.event.inputs.service_project }}" \
          "${{ github.event.inputs.host_project }}" \
          "${{ github.event.inputs.region }}" \
          "${{ github.event.inputs.zone }}" \
          "${{ github.event.inputs.host_vpc }}" \
          "${{ github.event.inputs.subnet_name }}" \
          "${{ github.event.inputs.workbench_name }}" \
          "${{ github.event.inputs.cmek_key }}" \
          "${{ github.event.inputs.machine_type }}" \
          "${{ github.event.inputs.owner_email }}" \
          "${{ github.event.inputs.cloud_eng_group }}" \
          "${{ github.event.inputs.customer_group_email }}"
        shell: bash
```

**2. Main script (`create_workbench.sh` - to be placed in your home directory):**

```bash
#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ========== INPUT VARIABLES (Command-line arguments) ==========
SERVICE_PROJECT="$1"
HOST_PROJECT="$2"
REGION="$3"
ZONE="$4"
HOST_VPC="$5"
SUBNET_NAME="$6"
WORKBENCH_NAME="$7"
CMEK_KEY="$8"
MACHINE_TYPE="$9"
OWNER_EMAIL="${10}"
CLOUD_ENG_GROUP="${11}"
CUSTOMER_GROUP_EMAIL="${12}"

# Validate that required variables are set
if [[ -z "$SERVICE_PROJECT" || -z "$HOST_PROJECT" || -z "$REGION" || -z "$ZONE" || -z "$HOST_VPC" || -z "$SUBNET_NAME" || -z "$WORKBENCH_NAME" || -z "$CMEK_KEY" || -z "$MACHINE_TYPE" || -z "$OWNER_EMAIL" || -z "$CLOUD_ENG_GROUP" || -z "$CUSTOMER_GROUP_EMAIL" ]]; then
  echo "ERROR: Not all required variables were provided.  Please provide 12 arguments in the following order:"
  echo "  SERVICE_PROJECT HOST_PROJECT REGION ZONE HOST_VPC SUBNET_NAME WORKBENCH_NAME CMEK_KEY MACHINE_TYPE OWNER_EMAIL CLOUD_ENG_GROUP CUSTOMER_GROUP_EMAIL"
  exit 1
fi

# ========== DERIVED VARIABLES ==========
SERVICE_ACCOUNT="vertexai@$SERVICE_PROJECT.iam.gserviceaccount.com"
NOTEBOOK_SERVICE_AGENT="service-$SERVICE_PROJECT_NUMBER@gcp-sa-notebooks.iam.gserviceaccount.com" # Added Notebook SA
SUBNET_RESOURCE="projects/$HOST_PROJECT/regions/$REGION/subnetworks/$SUBNET_NAME"
FULL_NETWORK="projects/$HOST_PROJECT/global/networks/$HOST_VPC"
ENVIRONMENT="nonprod" # Hardcoded, you might want to make this a user input
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

# Function to check if an element exists in an array
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

# Function to execute local group script
execute_local_group_script() {
  local host_project="$1"
  local service_account_email="$2"

  case "$host_project" in
    "HOST_PROJECT1")
      echo "Executing local-group1.sh for HOST_PROJECT1"
      bash local-group1.sh "$service_account_email"
      ;;
    "HOST_PROJECT2")
      echo "Executing local-group2.sh for HOST_PROJECT2"
      bash local-group2.sh "$service_account_email"
      ;;
    "HOST_PROJECT3")
      echo "Executing local-group3.sh for HOST_PROJECT3"
      bash local-group3.sh "$service_account_email"
      ;;
    *)
      echo "WARNING: No local group script defined for HOST_PROJECT: $host_project. Skipping."
      ;;
  esac
}



# Enable APIs in the service project
echo "Enabling APIs in project: $SERVICE_PROJECT"
for api in "${APIS[@]}"; do
  echo "Enabling API: $api"
  gcloud services enable "$api" --project="$SERVICE_PROJECT"
done

# Retrieve the service project number
SERVICE_PROJECT_NUMBER=$(gcloud projects describe "$SERVICE_PROJECT" --format="value(projectNumber)")

# Mapping of APIs to their corresponding service agents
declare -A SERVICE_AGENTS=(
  [dataflow.googleapis.com]="service-PROJECT_NUMBER@dataflow-service-producer-prod.iam.gserviceaccount.com"
  [dataform.googleapis.com]="service-PROJECT_NUMBER@gcp-sa-dataform.iam.gserviceaccount.com"
  [aiplatform.googleapis.com]="service-PROJECT_NUMBER@gcp-sa-aiplatform.iam.gserviceaccount.com"
  [notebooks.googleapis.com]="service-PROJECT_NUMBER@gcp-sa-notebooks.iam.gserviceaccount.com"
  [dataproc.googleapis.com]="service-PROJECT_NUMBER@dataproc-accounts.iam.gserviceaccount.com"
  [composer.googleapis.com]="service-PROJECT_NUMBER@gcp-sa-composer.iam.gserviceaccount.com"
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
    gcloud beta services identity create --service="$api" --project="$SERVICE_PROJECT" || true
  fi
done

# Wait for service agents to become available
echo "Waiting for service agents to become available..."
sleep 7


# Assign roles to service agents for each CMEK key
for location in "${LOCATIONS[@]}"; do
  KEY_RING="key-$location"
  KEY_NAME="key-${SERVICE_PROJECT}-${location}" # Use the user-provided SERVICE_PROJECT

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

# ========== STEP 0: Add Notebook Service Agent to Local Group  ==========
echo "Adding Notebook Service Agent to local group for HOST_PROJECT: $HOST_PROJECT"
execute_local_group_script "$HOST_PROJECT" "$NOTEBOOK_SERVICE_AGENT"

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
```

**3. Local Group Scripts (to be placed in your home directory):**

   **`local-group1.sh`:**

   ```bash
   #!/bin/bash
   # Add user to local-group-1
   GRP="local-group-1"
   SA="$1" # The service account email is passed as the first argument
   echo "Adding $SA to $GRP"
   gcloud identity groups memberships add --group-email="$GRP" --member-email="$SA"
   ```

   **`local-group2.sh`:**

   ```bash
   #!/bin/bash
   # Add user to local-group-2
   GRP="local-group-2"
   SA="$1"
   echo "Adding $SA to $GRP"
   gcloud identity groups memberships add --group-email="$GRP" --member-email="$SA"
   ```

   **`local-group3.sh`:**

   ```bash
   #!/bin/bash
   # Add user to local-group-3
   GRP="local-group-3"
   SA="$1"
   echo "Adding $SA to $GRP"
   gcloud identity groups memberships add --group-email="$GRP" --member-email="$SA"
   ```
