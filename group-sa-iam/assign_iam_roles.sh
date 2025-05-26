#!/bin/bash
set -euo pipefail

# assign_iam_roles.sh
# This script automates assigning IAM roles to a Google Service Account and/or an Active Directory Group
# within a GCP project. It supports dry-run and apply modes.
# It uses ETags for optimistic concurrency control and ensures no role conditions are set.
# This version allows assigning roles to a Service Account, an AD Group, or both in a single run.

# --- Configuration and Argument Parsing ---

MODE=""
GCP_PROJECT_ID=""
GCP_SERVICE_ACCOUNT_EMAIL="" # Optional: Email of the Service Account
AD_GROUP_EMAIL=""         # Optional: Email of the AD Group
IAM_ROLES_SA=""           # Comma-separated list of individual roles for the Service Account
IAM_ROLES_AD=""           # Comma-separated list of individual roles for the AD Group
BUNDLED_ROLES_SA=""       # Name of bundled role for Service Account (e.g., "GenAI_ADMIN")
BUNDLED_ROLES_AD=""       # Name of bundled role for AD Group (e.g., "GenAI_DEVELOPER")

# Function to display usage information
usage() {
  echo "Usage: $0 --mode <dry-run|apply> --project-id <GCP_PROJECT_ID> \\"
  echo "          [--service-account-email <SA_EMAIL>] [--ad-group-email <AD_GROUP_EMAIL>] \\"
  echo "          [--roles-sa <ROLE1,ROLE2>] [--roles-ad <ROLE1,ROLE2>] \\"
  echo "          [--bundled-roles-sa <BUNDLE_NAME>] [--bundled-roles-ad <BUNDLE_NAME>]"
  echo ""
  echo "Arguments:"
  echo "  --mode                  : Operation mode: 'dry-run' (show changes) or 'apply' (implement changes)."
  echo "  --project-id            : The GCP Project ID."
  echo "  --service-account-email : (Optional) The email of the GCP Service Account to assign roles to."
  echo "  --ad-group-email        : (Optional) The email of the Active Directory Group to assign roles to (must be synced to GCP)."
  echo "  --roles-sa              : (Optional, used if --service-account-email is provided) Comma-separated individual IAM roles for the Service Account."
  echo "  --roles-ad              : (Optional, used if --ad-group-email is provided) Comma-separated individual IAM roles for the AD Group."
  echo "  --bundled-roles-sa      : (Optional, used if --service-account-email is provided) Name of a predefined bundled role for the Service Account."
  echo "  --bundled-roles-ad      : (Optional, used if --ad-group-email is provided) Name of a predefined bundled role for the AD Group."
  echo ""
  echo "Note: At least one of --service-account-email or --ad-group-email must be provided."
  echo "Note: If --service-account-email is provided, at least one of --roles-sa or --bundled-roles-sa must also be provided."
  echo "Note: If --ad-group-email is provided, at least one of --roles-ad or --bundled-roles-ad must also be provided."
  exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift
      ;;
    --project-id)
      GCP_PROJECT_ID="$2"
      shift
      ;;
    --service-account-email)
      GCP_SERVICE_ACCOUNT_EMAIL="$2"
      shift
      ;;
    --ad-group-email)
      AD_GROUP_EMAIL="$2"
      shift
      ;;
    --roles-sa)
      IAM_ROLES_SA="$2"
      shift
      ;;
    --roles-ad)
      IAM_ROLES_AD="$2"
      shift
      ;;
    --bundled-roles-sa)
      BUNDLED_ROLES_SA="$2"
      shift
      ;;
    --bundled-roles-ad)
      BUNDLED_ROLES_AD="$2"
      shift
      ;;
    *)
      echo "Unknown parameter: $1"
      usage
      ;;
  esac
  shift
done

# --- Validate required arguments ---
if [[ -z "$MODE" || -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: --mode and --project-id are required."
  usage
fi

if [[ "$MODE" != "dry-run" && "$MODE" != "apply" ]]; then
  echo "Error: --mode must be 'dry-run' or 'apply'."
  usage
fi

# At least one target (SA or AD Group) must be provided
if [[ -z "$GCP_SERVICE_ACCOUNT_EMAIL" && -z "$AD_GROUP_EMAIL" ]]; then
  echo "Error: At least one of --service-account-email or --ad-group-email must be provided."
  usage
fi

# Validate roles for Service Account if provided
if [[ -n "$GCP_SERVICE_ACCOUNT_EMAIL" ]]; then
  if [[ -z "$IAM_ROLES_SA" && -z "$BUNDLED_ROLES_SA" ]]; then
    echo "Error: If --service-account-email is provided, at least one of --roles-sa or --bundled-roles-sa must also be provided."
    usage
  fi
fi

# Validate roles for AD Group if provided
if [[ -n "$AD_GROUP_EMAIL" ]]; then
  if [[ -z "$IAM_ROLES_AD" && -z "$BUNDLED_ROLES_AD" ]]; then
    echo "Error: If --ad-group-email is provided, at least one of --roles-ad or --bundled-roles-ad must also be provided."
    usage
  fi
fi


echo "--- Starting IAM Role Assignment Script ($MODE mode) ---"
echo "Project ID: $GCP_PROJECT_ID"
echo "Service Account: ${GCP_SERVICE_ACCOUNT_EMAIL:-None}"
echo "AD Group: ${AD_GROUP_EMAIL:-None}"
echo "Individual Roles for SA: ${IAM_ROLES_SA:-None}"
echo "Bundled Role for SA: ${BUNDLED_ROLES_SA:-None}"
echo "Individual Roles for AD Group: ${IAM_ROLES_AD:-None}"
echo "Bundled Role for AD Group: ${BUNDLED_ROLES_AD:-None}"
echo "------------------------------------------------------"

# --- Pre-checks and Setup ---

# Check for gcloud and jq CLI tools
if ! command -v gcloud &> /dev/null; then
  echo "Error: gcloud CLI not found. Please ensure it's installed and in your PATH."
  exit 1
fi
if ! command -v jq &> /dev/null; then
  echo "Error: jq not found. Please ensure it's installed (e.g., sudo apt-get install jq or brew install jq)."
  exit 1
fi

echo "Setting gcloud project to $GCP_PROJECT_ID..."
# Set the gcloud project context for subsequent commands
gcloud config set project "$GCP_PROJECT_ID" --quiet

# --- Function to resolve bundled roles ---
# This function takes a bundled role name and returns a comma-separated string of actual IAM roles.
get_bundled_roles() {
  local bundle_name="$1"
  local roles=""
  case "$bundle_name" in
    "GenAI_ADMIN")
      roles="roles/aiplatform.admin,roles/aiplatform.user,roles/notebooks.admin,roles/storage.admin,roles/bigquery.admin"
      ;;
    "GenAI_DEVELOPER")
      roles="roles/aiplatform.user,roles/viewer,roles/bigquery.dataViewer,roles/storage.objectViewer"
      ;;
    # Add more bundled roles here as needed
    "CUSTOM_BUNDLE_1")
      roles="roles/compute.admin,roles/container.admin"
      ;;
    *)
      echo "Error: Unknown bundled role name: '$bundle_name'. Please check the script's 'get_bundled_roles' function." >&2
      exit 1
      ;;
  esac
  echo "$roles"
}

# --- Core Logic: Get, Modify, Set IAM Policy ---

echo "Fetching current IAM policy for project $GCP_PROJECT_ID..."
# Retrieve the current IAM policy in JSON format
CURRENT_POLICY_JSON=$(gcloud projects get-iam-policy "$GCP_PROJECT_ID" --format=json)

if [[ -z "$CURRENT_POLICY_JSON" ]]; then
  echo "Error: Failed to retrieve current IAM policy for project $GCP_PROJECT_ID."
  exit 1
fi

echo "Current policy fetched successfully."

# Initialize MODIFIED_POLICY_JSON with the current policy.
# We will manipulate this JSON object using jq.
MODIFIED_POLICY_JSON="$CURRENT_POLICY_JSON"

# Function to add or update a member in a role binding within the policy JSON.
# Arguments:
#   $1 = current policy JSON string
#   $2 = role to add/update (e.g., "roles/viewer")
#   $3 = member type (e.g., "serviceAccount", "group", "user")
#   $4 = member email (e.g., "my-sa@project.iam.gserviceaccount.com", "ad-group@example.com")
add_or_update_member() {
  local policy_json="$1"
  local role="$2"
  local member_type="$3"
  local member_email="$4"
  local member_string="${member_type}:${member_email}"

  # Check if a binding for this specific role already exists in the policy.
  # jq -e will exit with 1 if no match is found, which is handled by set -e.
  local role_exists=$(echo "$policy_json" | jq --arg role "$role" '.bindings[] | select(.role == $role)')

  if [[ -z "$role_exists" ]]; then
    # If the role binding does not exist, add a new binding for this role and member.
    echo "  Adding new binding for role '$role' with member '$member_string'."
    policy_json=$(echo "$policy_json" | jq --arg role "$role" --arg member "$member_string" '
      .bindings += [{
        "role": $role,
        "members": [$member]
        # Condition is explicitly omitted as per requirement ("set the role condition to none").
        # gcloud prefers 'condition' to be absent if no condition is needed, rather than 'null'.
      }]
    ')
  else
    # If the role binding exists, check if the member is already part of this binding.
    local member_in_role=$(echo "$policy_json" | jq --arg role "$role" --arg member "$member_string" '
      .bindings[] | select(.role == $role) | .members[] | select(. == $member)
    ')

    if [[ -z "$member_in_role" ]]; then
      # If the member is not in the existing role binding, add them.
      echo "  Adding member '$member_string' to existing role '$role'."
      policy_json=$(echo "$policy_json" | jq --arg role "$role" --arg member "$member_string" '
        .bindings |= map(
          if .role == $role then
            # Append the new member to the members array
            .members += [$member]
          else
            . # Keep other bindings unchanged
          end
        )
      ')
    else
      echo "  Member '$member_string' already exists in role '$role'. Skipping."
    fi
  fi
  echo "$policy_json" # Return the modified policy JSON
}

# --- Process Roles for Service Account if provided ---
if [[ -n "$GCP_SERVICE_ACCOUNT_EMAIL" ]]; then
  ALL_SA_ROLES=""
  if [[ -n "$IAM_ROLES_SA" ]]; then
    ALL_SA_ROLES="$IAM_ROLES_SA"
  fi
  if [[ -n "$BUNDLED_ROLES_SA" ]]; then
    BUNDLED_ROLES_RESOLVED=$(get_bundled_roles "$BUNDLED_ROLES_SA")
    if [[ -n "$ALL_SA_ROLES" ]]; then
      ALL_SA_ROLES="${ALL_SA_ROLES},${BUNDLED_ROLES_RESOLVED}"
    else
      ALL_SA_ROLES="$BUNDLED_ROLES_RESOLVED"
    fi
  fi

  if [[ -n "$ALL_SA_ROLES" ]]; then
    echo "Processing roles for Service Account: $GCP_SERVICE_ACCOUNT_EMAIL"
    # Split the comma-separated roles string into an array
    IFS=',' read -ra SA_ROLES_ARRAY <<< "$ALL_SA_ROLES"
    for role in "${SA_ROLES_ARRAY[@]}"; do
      # Trim whitespace from role name
      role=$(echo "$role" | xargs)
      if [[ -n "$role" ]]; then # Ensure role is not empty after trimming
        # Call the function to add or update the service account for each role
        MODIFIED_POLICY_JSON=$(add_or_update_member "$MODIFIED_POLICY_JSON" "$role" "serviceAccount" "$GCP_SERVICE_ACCOUNT_EMAIL")
      fi
    done
  else
    echo "No roles specified for Service Account. Skipping."
  fi
fi

# --- Process Roles for AD Group if provided ---
if [[ -n "$AD_GROUP_EMAIL" ]]; then
  ALL_AD_ROLES=""
  if [[ -n "$IAM_ROLES_AD" ]]; then
    ALL_AD_ROLES="$IAM_ROLES_AD"
  fi
  if [[ -n "$BUNDLED_ROLES_AD" ]]; then
    BUNDLED_ROLES_RESOLVED=$(get_bundled_roles "$BUNDLED_ROLES_AD")
    if [[ -n "$ALL_AD_ROLES" ]]; then
      ALL_AD_ROLES="${ALL_AD_ROLES},${BUNDLED_ROLES_RESOLVED}"
    else
      ALL_AD_ROLES="$BUNDLED_ROLES_RESOLVED"
    fi
  fi

  if [[ -n "$ALL_AD_ROLES" ]]; then
    echo "Processing roles for AD Group: $AD_GROUP_EMAIL"
    # Split the comma-separated roles string into an array
    IFS=',' read -ra AD_ROLES_ARRAY <<< "$ALL_AD_ROLES"
    for role in "${AD_ROLES_ARRAY[@]}"; do
      # Trim whitespace from role name
      role=$(echo "$role" | xargs)
      if [[ -n "$role" ]]; then # Ensure role is not empty after trimming
        # Call the function to add or update the AD group for each role
        MODIFIED_POLICY_JSON=$(add_or_update_member "$MODIFIED_POLICY_JSON" "$role" "group" "$AD_GROUP_EMAIL")
      fi
    done
  else
    echo "No roles specified for AD Group. Skipping."
  fi
fi

# --- Dry Run vs. Apply ---

if [[ "$MODE" == "dry-run" ]]; then
  echo "--- Dry Run Output (Proposed IAM Policy) ---"
  # Print the final modified policy JSON in a human-readable format
  echo "$MODIFIED_POLICY_JSON" | jq .
  echo "--- End Dry Run Output ---"
  echo "Validation successful: Proposed changes are displayed above. No changes have been applied to GCP."
  # Exit with 0 to indicate success for GitHub Actions
  exit 0
elif [[ "$MODE" == "apply" ]]; then
  echo "Applying modified IAM policy to project $GCP_PROJECT_ID..."
  # Extract the ETag from the original policy. This is crucial for optimistic concurrency.
  ETAG=$(echo "$CURRENT_POLICY_JSON" | jq -r '.etag')
  if [[ -z "$ETAG" ]]; then
    echo "Error: ETag not found in current policy. Cannot apply changes safely without an ETag."
    exit 1
  fi

  # Add the ETag to the modified policy JSON before applying it.
  # The `set-iam-policy` command requires the ETag from the policy it's modifying.
  FINAL_POLICY_TO_APPLY=$(echo "$MODIFIED_POLICY_JSON" | jq --arg etag "$ETAG" '.etag = $etag')

  # Apply the policy using gcloud. We pipe the JSON directly to stdin.
  APPLY_RESULT=$(echo "$FINAL_POLICY_TO_APPLY" | gcloud projects set-iam-policy "$GCP_PROJECT_ID" --policy-file=/dev/stdin --format=json)

  if [[ -z "$APPLY_RESULT" ]]; then
    echo "Error: Failed to apply IAM policy. Check gcloud output for details."
    exit 1
  fi

  echo "IAM policy applied successfully."
  echo "New policy after application:"
  echo "$APPLY_RESULT" | jq . # Print the policy returned by gcloud after successful application
fi

echo "--- Script Finished ---"
