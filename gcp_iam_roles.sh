#!/bin/bash
set -euo pipefail
# Uncomment the line below for extremely verbose debugging (shows every command executed)
# set -x

# assign_iam_roles.sh
# This script automates assigning IAM roles to a Google Service Account or an Active Directory Group
# within a GCP project. It supports dry-run and apply modes.
# It uses ETags for optimistic concurrency control and ensures no role conditions are set.
# This version allows selecting the target (Service Account or AD Group) via a dropdown
# and supports optional bundled IAM roles (job functions).

# --- Configuration and Argument Parsing ---

MODE=""
GCP_PROJECT_ID=""
TARGET_TYPE=""          # "service_account" or "ad_group"
GCP_SERVICE_ACCOUNT_EMAIL="" # Only relevant if TARGET_TYPE is "service_account"
AD_GROUP_EMAIL=""       # Only relevant if TARGET_TYPE is "ad_group"
IAM_ROLES_SA=""         # Comma-separated list of individual roles for the Service Account
IAM_ROLES_AD=""         # Comma-separated list of individual roles for the AD Group
BUNDLED_ROLES_SA=""     # Name of bundled role for Service Account (e.g., "GenAI_ADMIN")
BUNDLED_ROLES_AD=""     # Name of bundled role for AD Group (e.g., "GenAI_DEVELOPER")

# Function to display usage information
usage() {
  echo "Usage: $0 --mode <dry-run|apply> --project-id <GCP_PROJECT_ID> \\"
  echo "          --target-type <service_account|ad_group> \\"
  echo "          [--service-account-email <SA_EMAIL>] [--ad-group-email <AD_GROUP_EMAIL>] \\"
  echo "          [--roles-sa <ROLE1,ROLE2>] [--roles-ad <ROLE1,ROLE2>] \\"
  echo "          [--bundled-roles-sa <BUNDLE_NAME>] [--bundled-roles-ad <BUNDLE_NAME>]"
  echo ""
  echo "Arguments:"
  echo "  --mode                    : Operation mode: 'dry-run' (show changes) or 'apply' (implement changes)."
  echo "  --project-id              : The GCP Project ID."
  echo "  --target-type             : The type of principal to assign roles to: 'service_account' or 'ad_group'."
  echo "  --service-account-email   : (Required if --target-type is 'service_account') The email of the GCP Service Account."
  echo "  --ad-group-email          : (Required if --target-type is 'ad_group') The email of the Active Directory Group (must be synced to GCP)."
  echo "  --roles-sa                : (Optional, used with --target-type service_account) Comma-separated individual IAM roles for the Service Account."
  echo "  --roles-ad                : (Optional, used with --target-type ad_group) Comma-separated individual IAM roles for the AD Group."
  echo "  --bundled-roles-sa        : (Optional, used with --target-type service_account) Name of a predefined bundled role for the Service Account."
  echo "  --bundled-roles-ad        : (Optional, used with --target-type ad_group) Name of a predefined bundled role for the AD Group."
  echo ""
  echo "Note: If --target-type is 'service_account', at least one of --roles-sa or --bundled-roles-sa must be provided."
  echo "Note: If --target-type is 'ad_group', at least one of --roles-ad or --bundled-roles-ad must be provided."
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
    --target-type)
      TARGET_TYPE="$2"
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
      echo "Unknown parameter: $1" >&2
      usage
      ;;
  esac
  shift
done

# --- Validate required arguments based on target type ---
echo "Validating script arguments..."
if [[ -z "$MODE" || -z "$GCP_PROJECT_ID" || -z "$TARGET_TYPE" ]]; then
  echo "Error: --mode, --project-id, and --target-type are required." >&2
  usage
fi

if [[ "$MODE" != "dry-run" && "$MODE" != "apply" ]]; then
  echo "Error: --mode must be 'dry-run' or 'apply'." >&2
  usage
fi

if [[ "$TARGET_TYPE" != "service_account" && "$TARGET_TYPE" != "ad_group" ]]; then
  echo "Error: --target-type must be 'service_account' or 'ad_group'." >&2
  usage
fi

if [[ "$TARGET_TYPE" == "service_account" ]]; then
  if [[ -z "$GCP_SERVICE_ACCOUNT_EMAIL" ]]; then
    echo "Error: --service-account-email is required when --target-type is 'service_account'." >&2
    usage
  fi
  if [[ -z "$IAM_ROLES_SA" && -z "$BUNDLED_ROLES_SA" ]]; then
    echo "Error: At least one of --roles-sa or --bundled-roles-sa must be provided for the Service Account." >&2
    echo "This is required to ensure that there's always at least one role to process." >&2
    usage
  fi
elif [[ "$TARGET_TYPE" == "ad_group" ]]; then
  if [[ -z "$AD_GROUP_EMAIL" ]]; then
    echo "Error: --ad-group-email is required when --target-type is 'ad_group'." >&2
    usage
  fi
  if [[ -z "$IAM_ROLES_AD" && -z "$BUNDLED_ROLES_AD" ]]; then
    echo "Error: At least one of --roles-ad or --bundled-roles-ad must be provided for the AD Group." >&2
    echo "This is required to ensure that there's always at least one role to process." >&2
    usage
  fi
fi
echo "Script arguments validated successfully."

echo "--- Starting IAM Role Assignment Script ($MODE mode) ---"
echo "Project ID: $GCP_PROJECT_ID"
echo "Target Type: $TARGET_TYPE"
if [[ "$TARGET_TYPE" == "service_account" ]]; then
  echo "Service Account: $GCP_SERVICE_ACCOUNT_EMAIL"
  echo "Individual Roles for SA: ${IAM_ROLES_SA:-None}"
  echo "Bundled Role for SA: ${BUNDLED_ROLES_SA:-None}"
elif [[ "$TARGET_TYPE" == "ad_group" ]]; then
  echo "AD Group: $AD_GROUP_EMAIL"
  echo "Individual Roles for AD Group: ${IAM_ROLES_AD:-None}"
  echo "Bundled Role for AD Group: ${BUNDLED_ROLES_AD:-None}"
fi
echo "------------------------------------------------------"

# --- Pre-checks and Setup ---

if ! command -v gcloud &> /dev/null; then
  echo "Error: gcloud CLI not found. Please ensure it's installed and in your PATH." >&2
  exit 1
fi
if ! command -v jq &> /dev/null; then
  echo "Error: jq not found. Please ensure it's installed (e.g., sudo apt-get install jq or brew install jq)." >&2
  exit 1
fi

echo "Setting gcloud project to $GCP_PROJECT_ID..."
GCLOUD_CONFIG_STDERR_FILE=$(mktemp)
if ! gcloud config set project "$GCP_PROJECT_ID" --quiet 2> "$GCLOUD_CONFIG_STDERR_FILE"; then
    echo "Error: Failed to set gcloud project context for Project ID: '$GCP_PROJECT_ID'." >&2
    cat "$GCLOUD_CONFIG_STDERR_FILE" >&2
    rm -f "$GCLOUD_CONFIG_STDERR_FILE"
    exit 1
fi
GCLOUD_CONFIG_STDERR_CONTENT=$(cat "$GCLOUD_CONFIG_STDERR_FILE")
if [[ -n "$GCLOUD_CONFIG_STDERR_CONTENT" ]]; then
    echo "Warning: gcloud config set project produced stderr output:" >&2
    echo "$GCLOUD_CONFIG_STDERR_CONTENT" >&2
fi
rm -f "$GCLOUD_CONFIG_STDERR_FILE"
echo "Gcloud project set to $GCP_PROJECT_ID."


echo "Fetching current IAM policy for project $GCP_PROJECT_ID..."
GCLOUD_GET_POLICY_STDOUT_FILE=$(mktemp)
GCLOUD_GET_POLICY_STDERR_FILE=$(mktemp)

# We use --quiet to minimize non-JSON output on stderr from gcloud itself for successful commands.
# Errors will still go to stderr.
if ! gcloud projects get-iam-policy "$GCP_PROJECT_ID" --format=json --quiet > "$GCLOUD_GET_POLICY_STDOUT_FILE" 2> "$GCLOUD_GET_POLICY_STDERR_FILE"; then
    echo "Error: 'gcloud projects get-iam-policy \"$GCP_PROJECT_ID\" --format=json' command failed." >&2
    echo "Stderr:" >&2
    cat "$GCLOUD_GET_POLICY_STDERR_FILE" >&2
    echo "Stdout (if any):" >&2
    cat "$GCLOUD_GET_POLICY_STDOUT_FILE" >&2
    rm -f "$GCLOUD_GET_POLICY_STDOUT_FILE" "$GCLOUD_GET_POLICY_STDERR_FILE"
    exit 1
fi

GCLOUD_GET_POLICY_STDERR_CONTENT=$(cat "$GCLOUD_GET_POLICY_STDERR_FILE")
if [[ -n "$GCLOUD_GET_POLICY_STDERR_CONTENT" ]]; then
    # Log stderr from gcloud get-iam-policy, as it might contain warnings or important info even on success
    echo "Stderr from 'gcloud projects get-iam-policy' (even on success):" >&2
    echo "$GCLOUD_GET_POLICY_STDERR_CONTENT" >&2
fi

CURRENT_POLICY_JSON_RAW=$(cat "$GCLOUD_GET_POLICY_STDOUT_FILE")
rm -f "$GCLOUD_GET_POLICY_STDOUT_FILE" "$GCLOUD_GET_POLICY_STDERR_FILE"

if [[ -z "$CURRENT_POLICY_JSON_RAW" ]]; then
  echo "Error: Fetched IAM policy for project '$GCP_PROJECT_ID' is empty. This is unexpected." >&2
  echo "This could indicate an issue with the 'gcloud projects get-iam-policy' command or insufficient permissions even if the command succeeded." >&2
  exit 1
fi

echo "--- DEBUG: Raw JSON fetched from gcloud projects get-iam-policy ---"
echo "$CURRENT_POLICY_JSON_RAW"
echo "--- END RAW DEBUG ---"

echo "Validating and parsing fetched IAM policy with jq..."
JQ_ERROR_LOG_FILE=$(mktemp)
# Parse the raw JSON. This will also pretty-print it, which is fine for MODIFIED_POLICY_JSON.
# CURRENT_POLICY_JSON will hold this initial, validated policy.
CURRENT_POLICY_JSON=$(echo "$CURRENT_POLICY_JSON_RAW" | jq '.' 2> "$JQ_ERROR_LOG_FILE")
JQ_PARSE_EXIT_CODE=$?

if [[ $JQ_PARSE_EXIT_CODE -ne 0 ]]; then
  echo "ERROR: Failed to parse the IAM policy JSON fetched from GCP for project '$GCP_PROJECT_ID'." >&2
  echo "JQ exit code: $JQ_PARSE_EXIT_CODE" >&2
  echo "JQ parsing errors:" >&2
  cat "$JQ_ERROR_LOG_FILE" >&2
  echo "The raw JSON input provided to JQ (which was fetched from gcloud) was:" >&2
  echo "$CURRENT_POLICY_JSON_RAW" >&2
  echo "This often indicates one of the following:" >&2
  echo "  1. The Project ID ('$GCP_PROJECT_ID') is incorrect, does not exist, or you lack permissions." >&2
  echo "  2. The WIF executor SA ('$WIF_EXECUTOR_SA_EMAIL') lacks 'roles/resourcemanager.projectIamViewer' on project '$GCP_PROJECT_ID'." >&2
  echo "  3. WIF authentication failed." >&2
  echo "  4. 'gcloud' command produced non-JSON output on stdout despite '--format=json'." >&2
  rm -f "$JQ_ERROR_LOG_FILE"
  exit 1
fi
rm -f "$JQ_ERROR_LOG_FILE"
echo "Current IAM policy fetched and parsed successfully."

# MODIFIED_POLICY_JSON will be manipulated. Initialize it with the valid current policy.
MODIFIED_POLICY_JSON="$CURRENT_POLICY_JSON"


# Function to add or update a member in a role binding within the policy JSON.
# Arguments:
#   $1 = current policy JSON string
#   $2 = role to add/update (e.g., "roles/viewer")
#   $3 = member type (e.g., "serviceAccount", "group", "user")
#   $4 = member email (e.g., "my-sa@project.iam.gserviceaccount.com", "ad-group@example.com")
add_or_update_member() {
  local policy_json_input="$1" # Renamed to avoid confusion with function output
  local role="$2"
  local member_type="$3"
  local member_email="$4"
  local member_string="${member_type}:${member_email}"
  local temp_policy_json="" # To hold intermediate jq results
  local jq_op_stderr_file

  echo "    --- Entering add_or_update_member for role '$role', member '$member_string' ---"

  # Validate input JSON before proceeding (though it should be valid if initial parsing succeeded)
  if ! echo "$policy_json_input" | jq -e '.' >/dev/null 2>&1; then
    echo "    FATAL ERROR: Input JSON to add_or_update_member is not valid JSON. This should not happen if initial parsing was correct." >&2
    echo "    Problematic JSON snippet (first 500 chars): '$(echo "$policy_json_input" | head -c 500)'" >&2
    exit 1
  fi

  jq_op_stderr_file=$(mktemp)

  # Check if a binding for this specific role already exists in the policy.
  local role_exists_check
  role_exists_check=$(echo "$policy_json_input" | jq --arg role "$role" '.bindings[] | select(.role == $role)' 2> "$jq_op_stderr_file")
  if [[ $? -ne 0 && -s "$jq_op_stderr_file" ]]; then # Check if jq failed and produced stderr
      echo "    ERROR: jq failed to check for existing role binding for role '$role'." >&2
      cat "$jq_op_stderr_file" >&2
      rm -f "$jq_op_stderr_file"
      exit 1
  fi

  if [[ -z "$role_exists_check" ]]; then
    echo "    Adding new binding for role '$role' with member '$member_string'."
    temp_policy_json=$(echo "$policy_json_input" | jq --arg role "$role" --arg member "$member_string" '
      .bindings += [{
        "role": $role,
        "members": [$member]
        # Condition is explicitly omitted
      }]
    ' 2> "$jq_op_stderr_file")
    if [[ $? -ne 0 || -z "$temp_policy_json" ]]; then
      echo "    ERROR: jq failed to add new binding for role '$role', or produced empty output." >&2
      cat "$jq_op_stderr_file" >&2
      rm -f "$jq_op_stderr_file"
      exit 1
    fi
  else
    # If the role binding exists, check if the member is already part of this binding.
    local member_in_role_check
    member_in_role_check=$(echo "$policy_json_input" | jq --arg role "$role" --arg member "$member_string" '
      .bindings[] | select(.role == $role) | .members[] | select(. == $member)
    ' 2> "$jq_op_stderr_file")
    if [[ $? -ne 0 && -s "$jq_op_stderr_file" ]]; then
      echo "    ERROR: jq failed to check for existing member in role '$role'." >&2
      cat "$jq_op_stderr_file" >&2
      rm -f "$jq_op_stderr_file"
      exit 1
    fi

    if [[ -z "$member_in_role_check" ]]; then
      echo "    Adding member '$member_string' to existing role '$role'."
      temp_policy_json=$(echo "$policy_json_input" | jq --arg role "$role" --arg member "$member_string" '
        .bindings |= map(
          if .role == $role then
            .members += [$member] | .members |= unique # Ensure uniqueness after adding
          else
            .
          end
        )
      ' 2> "$jq_op_stderr_file")
      if [[ $? -ne 0 || -z "$temp_policy_json" ]]; then
        echo "    ERROR: jq failed to add member to existing role '$role', or produced empty output." >&2
        cat "$jq_op_stderr_file" >&2
        rm -f "$jq_op_stderr_file"
        exit 1
      fi
    else
      echo "    Member '$member_string' already exists in role '$role'. Skipping."
      temp_policy_json="$policy_json_input" # No change
    fi
  fi
  rm -f "$jq_op_stderr_file"
  echo "    --- Exiting add_or_update_member ---"
  echo "$temp_policy_json" # Return the modified policy JSON
}

# --- Function to resolve bundled roles ---
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

# --- Process Roles based on TARGET_TYPE ---
if [[ "$TARGET_TYPE" == "service_account" ]]; then
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
    IFS=',' read -ra SA_ROLES_ARRAY <<< "$ALL_SA_ROLES"
    for role in "${SA_ROLES_ARRAY[@]}"; do
      role=$(echo "$role" | xargs) # Trim whitespace
      if [[ -n "$role" ]]; then
        MODIFIED_POLICY_JSON=$(add_or_update_member "$MODIFIED_POLICY_JSON" "$role" "serviceAccount" "$GCP_SERVICE_ACCOUNT_EMAIL")
      fi
    done
  else
    echo "No roles specified for Service Account. Skipping."
  fi
elif [[ "$TARGET_TYPE" == "ad_group" ]]; then
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
    IFS=',' read -ra AD_ROLES_ARRAY <<< "$ALL_AD_ROLES"
    for role in "${AD_ROLES_ARRAY[@]}"; do
      role=$(echo "$role" | xargs) # Trim whitespace
      if [[ -n "$role" ]]; then
        MODIFIED_POLICY_JSON=$(add_or_update_member "$MODIFIED_POLICY_JSON" "$role" "group" "$AD_GROUP_EMAIL")
      fi
    done
  else
    echo "No roles specified for AD Group. Skipping."
  fi
fi

# --- Dry Run vs. Apply ---
JQ_FINAL_OUTPUT_STDERR_FILE=$(mktemp)

if [[ "$MODE" == "dry-run" ]]; then
  echo "--- Dry Run Output (Proposed IAM Policy) ---"
  echo "$MODIFIED_POLICY_JSON" | jq . 2> "$JQ_FINAL_OUTPUT_STDERR_FILE" || {
    echo "Error: jq failed to format final dry-run policy." >&2
    cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2
    rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"
    exit 1;
  }
  if [[ -s "$JQ_FINAL_OUTPUT_STDERR_FILE" ]]; then
      echo "Warning: jq produced stderr during final dry-run formatting:" >&2
      cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2
  fi
  echo "--- End Dry Run Output ---"
  echo "Validation successful: Proposed changes are displayed above. No changes have been applied to GCP."
elif [[ "$MODE" == "apply" ]]; then
  echo "Applying modified IAM policy to project $GCP_PROJECT_ID..."
  ETAG=$(echo "$CURRENT_POLICY_JSON" | jq -r '.etag' 2> "$JQ_FINAL_OUTPUT_STDERR_FILE")
  if [[ $? -ne 0 || -z "$ETAG" ]]; then
    echo "Error: Failed to extract ETag from current policy, or ETag is empty." >&2
    cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2
    rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"
    exit 1
  fi
   if [[ "$ETAG" == "null" ]]; then # If etag was literally null string
    echo "Error: ETag value is 'null'. Cannot apply changes safely." >&2
    rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"
    exit 1
  fi


  FINAL_POLICY_TO_APPLY=$(echo "$MODIFIED_POLICY_JSON" | jq --arg etag "$ETAG" '.etag = $etag' 2> "$JQ_FINAL_OUTPUT_STDERR_FILE")
  if [[ $? -ne 0 || -z "$FINAL_POLICY_TO_APPLY" ]]; then
    echo "Error: Failed to inject ETag into the modified policy using jq, or result was empty." >&2
    cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2
    rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"
    exit 1
  fi

  echo "--- DEBUG: Final policy to apply (with ETag) ---"
  echo "$FINAL_POLICY_TO_APPLY" | jq . # For debugging
  echo "--- END DEBUG ---"

  GCLOUD_SET_POLICY_STDERR_FILE=$(mktemp)
  APPLY_RESULT_JSON_FILE=$(mktemp)

  if ! echo "$FINAL_POLICY_TO_APPLY" | gcloud projects set-iam-policy "$GCP_PROJECT_ID" /dev/stdin --format=json --quiet > "$APPLY_RESULT_JSON_FILE" 2> "$GCLOUD_SET_POLICY_STDERR_FILE"; then
    echo "Error: 'gcloud projects set-iam-policy' command failed to apply the new policy." >&2
    echo "Gcloud Stderr:" >&2
    cat "$GCLOUD_SET_POLICY_STDERR_FILE" >&2
    echo "Gcloud Stdout (if any):" >&2
    cat "$APPLY_RESULT_JSON_FILE" >&2 # gcloud might output error structure to stdout
    rm -f "$GCLOUD_SET_POLICY_STDERR_FILE" "$APPLY_RESULT_JSON_FILE" "$JQ_FINAL_OUTPUT_STDERR_FILE"
    exit 1
  fi
  
  GCLOUD_SET_POLICY_STDERR_CONTENT=$(cat "$GCLOUD_SET_POLICY_STDERR_FILE")
  if [[ -n "$GCLOUD_SET_POLICY_STDERR_CONTENT" ]]; then
    echo "Warning: 'gcloud projects set-iam-policy' produced stderr output even on success:" >&2
    echo "$GCLOUD_SET_POLICY_STDERR_CONTENT" >&2
  fi

  APPLY_RESULT=$(cat "$APPLY_RESULT_JSON_FILE")
  rm -f "$GCLOUD_SET_POLICY_STDERR_FILE" "$APPLY_RESULT_JSON_FILE"

  echo "IAM policy applied successfully."
  echo "New policy after application:"
  echo "$APPLY_RESULT" | jq . 2> "$JQ_FINAL_OUTPUT_STDERR_FILE" || {
    echo "Error: jq failed to format the policy returned by 'set-iam-policy'." >&2
    echo "Raw output from gcloud was:" >&2
    echo "$APPLY_RESULT" >&2
    cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2
    rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"
    # Don't exit here as policy was applied, but formatting failed.
  }
fi

rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE" # Clean up if it exists
echo "--- Script Finished ---"
