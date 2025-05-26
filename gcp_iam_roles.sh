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
TARGET_TYPE=""            # "service_account" or "ad_group"
GCP_SERVICE_ACCOUNT_EMAIL="" # Only relevant if TARGET_TYPE is "service_account"
AD_GROUP_EMAIL=""         # Only relevant if "ad_group"
IAM_ROLES_SA=""           # Comma-separated list of individual roles for the Service Account
IAM_ROLES_AD=""           # Comma-separated list of individual roles for the AD Group
BUNDLED_ROLES_SA=""       # Name of bundled role for Service Account (e.g., "GenAI_ADMIN")
BUNDLED_ROLES_AD=""       # Name of bundled role for AD Group (e.g., "GenAI_DEVELOPER")

# Function to display usage information
usage() {
  echo "Usage: $0 --mode <dry-run|apply> --project-id <GCP_PROJECT_ID> \\"
  echo "          --target-type <service_account|ad_group> \\"
  echo "          [--service-account-email <SA_EMAIL>] [--ad-group-email <AD_GROUP_EMAIL>] \\"
  echo "          [--roles-sa <ROLE1,ROLE2>] [--roles-ad <ROLE1,ROLE2>] \\"
  echo "          [--bundled-roles-sa <BUNDLE_NAME>] [--bundled-roles-ad <BUNDLE_NAME>]"
  echo ""
  echo "Arguments:"
  echo "  --mode                      : Operation mode: 'dry-run' (show changes) or 'apply' (implement changes)."
  echo "  --project-id                : The GCP Project ID."
  echo "  --target-type               : The type of principal to assign roles to: 'service_account' or 'ad_group'."
  echo "  --service-account-email : (Required if --target-type is 'service_account') The email of the GCP Service Account."
  echo "  --ad-group-email          : (Required if --target-type is 'ad_group') The email of the Active Directory Group (must be synced to GCP)."
  echo "  --roles-sa                  : (Optional, used with --target-type service_account) Comma-separated individual IAM roles for the Service Account."
  echo "  --roles-ad                  : (Optional, used with --target-type ad_group) Comma-separated individual IAM roles for the AD Group."
  echo "  --bundled-roles-sa          : (Optional, used with --target-type service_account) Name of a predefined bundled role for the Service Account."
  echo "  --bundled-roles-ad          : (Optional, used with --target-type ad_group) Name of a predefined bundled role for the AD Group."
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

# Check for gcloud and jq CLI tools
if ! command -v gcloud &> /dev/null; then
  echo "Error: gcloud CLI not found. Please ensure it's installed and in your PATH." >&2
  exit 1
fi
if ! command -v jq &> /dev/null; then
  echo "Error: jq not found. Please ensure it's installed (e.g., sudo apt-get install jq or brew install jq)." >&2
  exit 1
fi

echo "Setting gcloud project to $GCP_PROJECT_ID..."
# Set the gcloud project context for subsequent commands
# Capture stderr to identify potential gcloud errors
gcloud config set project "$GCP_PROJECT_ID" --quiet 2> >(tee /dev/stderr) || { echo "Error: Failed to set gcloud project context. This might indicate an invalid Project ID: '$GCP_PROJECT_ID'." >&2; exit 1; }
echo "Gcloud project set to $GCP_PROJECT_ID."

echo "Fetching current IAM policy for project $GCP_PROJECT_ID with debug verbosity..."
# Retrieve the current IAM policy in JSON format with debug logging
# Capture stderr to identify potential gcloud errors, even if it exits 0
# IMPORTANT: Filter output to ensure only JSON is passed to jq.
# This sed command extracts content from the first '{' to the last '}'.
RAW_GCLOUD_OUTPUT=$(gcloud projects get-iam-policy "$GCP_PROJECT_ID" --format=json --verbosity=debug 2> >(tee /dev/stderr))
CURRENT_POLICY_JSON_RAW=$(echo "$RAW_GCLOUD_OUTPUT" | sed -n '/^{/,/}$/p')


if [[ -z "$CURRENT_POLICY_JSON_RAW" ]]; then
  echo "Error: Failed to retrieve or parse current IAM policy for project '$GCP_PROJECT_ID'." >&2
  echo "This often indicates one of the following:" >&2
  echo "  1. The Project ID is incorrect or does not exist." >&2
  echo "  2. The Workload Identity Federation (WIF) executor service account does not have sufficient permissions (e.g., roles/resourcemanager.projectIamViewer) on project '$GCP_PROJECT_ID'." >&2
  echo "  3. The Workload Identity Federation authentication itself failed." >&2
  echo "  4. The gcloud output did not contain valid JSON, even after filtering. Review the 'RAW_GCLOUD_OUTPUT' in logs for clues." >&2
  echo "Review the debug output above for more clues." >&2
  exit 1
fi

# --- UPDATED: JSON Cleanup Function (More Robust Error Handling) ---
cleanup_malformed_json() {
  local input_json="$1"
  local cleaned_json=""
  local jq_output=""
  local jq_exit_code=""

  echo "Attempting to clean up potentially malformed JSON policy (semicolons to colons)..."
  # Attempt initial fix: replace semicolons with colons
  cleaned_json=$(echo "$input_json" | sed -E 's/("[^"]+")\s*;\s*/\1: /g')

  echo "DEBUG: Attempting JQ validation and pretty-print on cleaned JSON."
  echo "DEBUG: Cleaned JSON for JQ validation:"
  echo "$cleaned_json"
  echo "DEBUG: End of Cleaned JSON for JQ validation."

  # Attempt to parse and pretty-print with jq.
  # Capture both stdout (the pretty JSON) and stderr (jq errors)
  jq_output=$(echo "$cleaned_json" | jq --raw-output '.' 2>&1) # Redirect stderr to stdout for capture
  jq_exit_code=$?

  if [[ $jq_exit_code -ne 0 ]]; then
    echo "ERROR: JQ failed to parse the JSON policy even after basic semicolon cleanup." >&2
    echo "This indicates a more fundamental JSON malformation (e.g., truncation, unmatched braces/quotes)." >&2
    echo "JQ's error message (from stderr):" >&2
    echo "$jq_output" >&2 # jq_output now contains the error message from jq
    echo "The problematic JSON input that JQ tried to parse was:" >&2
    echo "$cleaned_json" | head -n 40 >&2 # show first 40 lines to keep logs readable
    echo "..." >&2
    exit 1 # Script must exit as we cannot safely proceed with malformed JSON
  else
    echo "JSON policy cleanup successful. Policy is now valid JSON."
    echo "$jq_output" # Return the valid, pretty-printed JSON
  fi
}

# --- Apply Cleanup ---
echo "--- DEBUG: Raw JSON from gcloud (before cleanup) ---"
echo "$RAW_GCLOUD_OUTPUT" # Changed to RAW_GCLOUD_OUTPUT to see full original
echo "--- END RAW DEBUG ---"

# Call the cleanup function. It will exit if JSON is still malformed.
CURRENT_POLICY_JSON=$(cleanup_malformed_json "$CURRENT_POLICY_JSON_RAW")

echo "--- DEBUG: Content of CURRENT_POLICY_JSON after cleanup and before final ops ---"
echo "$CURRENT_POLICY_JSON"
echo "--- END DEBUG ---"


echo "Current policy fetched and cleaned successfully."

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
  local policy_json_input="$1" # Renamed to avoid confusion with function output
  local role="$2"
  local member_type="$3"
  local member_email="$4"
  local member_string="${member_type}:${member_email}"
  local temp_policy_json="" # To hold intermediate jq results

  echo "  --- Entering add_or_update_member for role '$role', member '$member_string' ---"
  echo "  DEBUG: Input policy_json_input (full content):"
  echo "$policy_json_input" # Print full input JSON for thorough debugging
  echo "  DEBUG: End of Input policy_json_input"

  # Crucial Check: Ensure policy_json_input is not empty/malformed before passing to jq
  if [[ -z "$policy_json_input" ]]; then
    echo "  FATAL ERROR: Input JSON to add_or_update_member is empty. Exiting." >&2
    exit 1
  fi
  # Use jq -e '.' to validate JSON. It returns 0 for valid JSON, 1 for invalid.
  if ! echo "$policy_json_input" | jq -e '.' >/dev/null 2>&1; then
    echo "  FATAL ERROR: Input JSON to add_or_update_member is not valid JSON." >&2
    echo "  Problematic JSON for jq validation in add_or_update_member:" >&2
    echo "$policy_json_input" | head -n 40 >&2
    echo "..." >&2
    exit 1
  fi


  # Check if a binding for this specific role already exists in the policy.
  # Use `jq -e` for robust checking. If it matches nothing, it exits non-zero, but that's okay.
  # If it's a parsing error, it will exit non-zero and print to stderr.
  local role_exists_check_output
  role_exists_check_output=$(echo "$policy_json_input" | jq --arg role "$role" '.bindings[] | select(.role == $role)' 2>&1)
  local jq_exit_code=$?

  if [[ $jq_exit_code -ne 0 ]]; then
    # If jq failed to parse the JSON *here*, then there's a problem.
    # We already validated input JSON, so this usually means 'bindings' is missing or empty,
    # which results in a non-zero exit but not a parse error.
    if [[ "$role_exists_check_output" == "parse error"* ]]; then
        echo "  ERROR: jq failed to check for existing role binding for role '$role' due to a parse error." >&2
        echo "  JQ Output (likely error): $role_exists_check_output" >&2
        exit 1 # Exit script if jq fails here
    fi
    # If jq_exit_code is non-zero but not a parse error, it means no match was found, which is intended.
    # So, continue to add a new binding.
    # Set role_exists_check to empty to trigger the "add new binding" path
    role_exists_check=""
  else
    # Role exists, capture the actual output if needed, but for now we just care if it found something
    role_exists_check="$role_exists_check_output"
  fi


  if [[ -z "$role_exists_check" ]]; then
    # If the role binding does not exist, add a new binding for this role and member.
    echo "  Adding new binding for role '$role' with member '$member_string'."
    temp_policy_json=$(echo "$policy_json_input" | jq --arg role "$role" --arg member "$member_string" '
      .bindings += [{
        "role": $role,
        "members": [$member]
        # Condition is explicitly omitted as per requirement ("set the role condition to none").
        # gcloud prefers 'condition' to be absent if no condition is needed, rather than 'null'.
      }]
    ' 2>&1) # Redirect jq errors to stdout for capture
    jq_exit_code=$?
    if [[ $jq_exit_code -ne 0 ]]; then
      echo "  ERROR: jq failed to add new binding for role '$role'. JQ Output: $temp_policy_json" >&2
      exit 1 # Exit script if jq fails here
    fi
    if [[ -z "$temp_policy_json" ]]; then # Check if jq produced empty output
      echo "  ERROR: jq command to add new binding produced empty output for role '$role'. Input JSON might be invalid or jq expression is incorrect." >&2
      exit 1
    fi
  else
    # If the role binding exists, check if the member is already part of this binding.
    local member_in_role_check_output
    member_in_role_check_output=$(echo "$policy_json_input" | jq --arg role "$role" --arg member "$member_string" '
      .bindings[] | select(.role == $role) | .members[] | select(. == $member)
    ' 2>&1) # Redirect stderr to stdout for capture
    jq_exit_code=$?

    if [[ $jq_exit_code -ne 0 ]]; then
        if [[ "$member_in_role_check_output" == "parse error"* ]]; then
            echo "  ERROR: jq failed to check for existing member in role '$role' due to a parse error." >&2
            echo "  JQ Output (likely error): $member_in_role_check_output" >&2
            exit 1 # Exit script if jq fails here
        fi
        member_in_role_check="" # No match or other non-error failure (e.g., empty array)
    else
        member_in_role_check="$member_in_role_check_output"
    fi

    if [[ -z "$member_in_role_check" ]]; then
      # If the member is not in the existing role binding, add them.
      echo "  Adding member '$member_string' to existing role '$role'."
      temp_policy_json=$(echo "$policy_json_input" | jq --arg role "$role" --arg member "$member_string" '
        .bindings |= map(
          if .role == $role then
            # Append the new member to the members array
            .members += [$member]
          else
            . # Keep other bindings unchanged
          end
        )
      ' 2>&1) # Redirect jq errors to stdout for capture
      jq_exit_code=$?
      if [[ $jq_exit_code -ne 0 ]]; then
        echo "  ERROR: jq failed to add member to existing role '$role'. JQ Output: $temp_policy_json" >&2
        exit 1 # Exit script if jq fails here
      fi
      if [[ -z "$temp_policy_json" ]]; then # Check if jq produced empty output
        echo "  ERROR: jq command to add member to existing role produced empty output for role '$role'. Input JSON might be invalid or jq expression is incorrect." >&2
        exit 1
      fi
    else
      echo "  Member '$member_string' already exists in role '$role'. Skipping."
      temp_policy_json="$policy_json_input" # No change, so keep original
    fi
  fi
  echo "  DEBUG: Output policy_json (full content):"
  echo "$temp_policy_json" # Print full output JSON for thorough debugging
  echo "  DEBUG: End of Output policy_json"
  echo "  --- Exiting add_or_update_member ---"
  echo "$temp_policy_json" # Return the modified policy JSON
}

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
  echo "$MODIFIED_POLICY_JSON" | jq . 2> >(tee /dev/stderr) # Redirect jq errors to stderr
  echo "--- End Dry Run Output ---"
  echo "Validation successful: Proposed changes are displayed above. No changes have been applied to GCP."
  # Exit with 0 to indicate success for GitHub Actions
  exit 0
elif [[ "$MODE" == "apply" ]]; then
  echo "Applying modified IAM policy to project $GCP_PROJECT_ID with debug verbosity..."
  # Extract the ETag from the original policy. This is crucial for optimistic concurrency.
  ETAG=$(echo "$CURRENT_POLICY_JSON" | jq -r '.etag' 2> >(tee /dev/stderr)) # Redirect jq errors to stderr
  if [[ -z "$ETAG" ]]; then
    echo "Error: ETag not found in current policy. Cannot apply changes safely without an ETag. This might indicate an issue with fetching the initial policy." >&2
    exit 1
  fi

  # Add the ETag to the modified policy JSON before applying it.
  # The `set-iam-policy` command requires the ETag from the policy it's modifying.
  FINAL_POLICY_TO_APPLY=$(echo "$MODIFIED_POLICY_JSON" | jq --arg etag "$ETAG" '.etag = $etag' 2> >(tee /dev/stderr)) # Redirect jq errors to stderr

  # Apply the policy using gcloud. We pipe the JSON directly to stdin.
  # Capture stderr to identify potential gcloud errors
  APPLY_RESULT=$(echo "$FINAL_POLICY_TO_APPLY" | gcloud projects set-iam-policy "$GCP_PROJECT_ID" --policy-file=/dev/stdin --format=json --verbosity=debug 2> >(tee /dev/stderr))

  if [[ -z "$APPLY_RESULT" ]]; then
    echo "Error: Failed to apply IAM policy. Check gcloud output for details." >&2
    echo "This typically indicates insufficient permissions for the executor service account (e.g., missing roles/iam.securityAdmin) on project '$GCP_PROJECT_ID'." >&2
    echo "Review the debug output above for more clues." >&2
    exit 1
  fi

  echo "IAM policy applied successfully."
  echo "New policy after application:"
  echo "$APPLY_RESULT" | jq . 2> >(tee /dev/stderr) # Print the policy returned by gcloud after successful application
fi

echo "--- Script Finished ---"
