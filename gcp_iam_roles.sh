#!/bin/bash
set -euo pipefail
# Uncomment the line below for extremely verbose debugging (shows every command executed)
# set -x

# --- Configuration and Argument Parsing ---
MODE=""
GCP_PROJECT_ID=""
TARGET_TYPE=""
GCP_SERVICE_ACCOUNT_EMAIL=""
AD_GROUP_EMAIL=""
IAM_ROLES_SA=""
IAM_ROLES_AD=""
BUNDLED_ROLES_SA=""
BUNDLED_ROLES_AD=""

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

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift ;;
    --project-id) GCP_PROJECT_ID="$2"; shift ;;
    --target-type) TARGET_TYPE="$2"; shift ;;
    --service-account-email)
      GCP_SERVICE_ACCOUNT_EMAIL=$(echo "$2" | xargs | sed 's/\*$//g') # Clean input email
      shift ;;
    --ad-group-email)
      AD_GROUP_EMAIL=$(echo "$2" | xargs | sed 's/\*$//g') # Clean input email
      shift ;;
    --roles-sa) IAM_ROLES_SA="$2"; shift ;;
    --roles-ad) IAM_ROLES_AD="$2"; shift ;;
    --bundled-roles-sa) BUNDLED_ROLES_SA="$2"; shift ;;
    --bundled-roles-ad) BUNDLED_ROLES_AD="$2"; shift ;;
    *) echo "Unknown parameter: $1" >&2; usage ;;
  esac
  shift
done

# --- Validate required arguments ---
echo "Validating script arguments..."
if [[ -z "$MODE" || -z "$GCP_PROJECT_ID" || -z "$TARGET_TYPE" ]]; then echo "Error: --mode, --project-id, and --target-type are required." >&2; usage; fi
if [[ "$MODE" != "dry-run" && "$MODE" != "apply" ]]; then echo "Error: --mode must be 'dry-run' or 'apply'." >&2; usage; fi
if [[ "$TARGET_TYPE" != "service_account" && "$TARGET_TYPE" != "ad_group" ]]; then echo "Error: --target-type must be 'service_account' or 'ad_group'." >&2; usage; fi

if [[ "$TARGET_TYPE" == "service_account" ]]; then
  if [[ -z "$GCP_SERVICE_ACCOUNT_EMAIL" ]]; then echo "Error: --service-account-email is required for target_type 'service_account'." >&2; usage; fi
  if [[ -z "$IAM_ROLES_SA" && -z "$BUNDLED_ROLES_SA" ]]; then echo "Error: At least one of --roles-sa or --bundled-roles-sa must be provided for Service Account." >&2; usage; fi
elif [[ "$TARGET_TYPE" == "ad_group" ]]; then
  if [[ -z "$AD_GROUP_EMAIL" ]]; then echo "Error: --ad-group-email is required for target_type 'ad_group'." >&2; usage; fi
  if [[ -z "$IAM_ROLES_AD" && -z "$BUNDLED_ROLES_AD" ]]; then echo "Error: At least one of --roles-ad or --bundled-roles-ad must be provided for AD Group." >&2; usage; fi
fi
echo "Script arguments validated."
echo "Cleaned Service Account Email (from input): '$GCP_SERVICE_ACCOUNT_EMAIL'"
echo "Cleaned AD Group Email (from input): '$AD_GROUP_EMAIL'"

# --- Info print ---
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
if ! command -v gcloud &> /dev/null; then echo "Error: gcloud CLI not found." >&2; exit 1; fi
if ! command -v jq &> /dev/null; then echo "Error: jq not found." >&2; exit 1; fi

echo "Setting gcloud project to $GCP_PROJECT_ID..."
GCLOUD_CONFIG_STDERR_FILE=$(mktemp)
# Capture stderr to identify potential gcloud errors
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
    echo "Stderr:" >&2; cat "$GCLOUD_GET_POLICY_STDERR_FILE" >&2
    echo "Stdout (if any):" >&2; cat "$GCLOUD_GET_POLICY_STDOUT_FILE" >&2
    rm -f "$GCLOUD_GET_POLICY_STDOUT_FILE" "$GCLOUD_GET_POLICY_STDERR_FILE"
    exit 1
fi
# Log stderr from gcloud get-iam-policy, as it might contain warnings or important info even on success
GCLOUD_GET_POLICY_STDERR_CONTENT=$(cat "$GCLOUD_GET_POLICY_STDERR_FILE")
if [[ -n "$GCLOUD_GET_POLICY_STDERR_CONTENT" ]]; then
    echo "Stderr from 'gcloud projects get-iam-policy' (even on success):" >&2
    echo "$GCLOUD_GET_POLICY_STDERR_CONTENT" >&2
fi
CURRENT_POLICY_JSON_RAW=$(cat "$GCLOUD_GET_POLICY_STDOUT_FILE")
rm -f "$GCLOUD_GET_POLICY_STDOUT_FILE" "$GCLOUD_GET_POLICY_STDERR_FILE" # Clean up temp files

if [[ -z "$CURRENT_POLICY_JSON_RAW" ]]; then
  echo "Error: Fetched IAM policy for project '$GCP_PROJECT_ID' is empty. This is unexpected." >&2
  exit 1
fi

echo "--- DEBUG: Raw JSON fetched from gcloud (length: ${#CURRENT_POLICY_JSON_RAW}) ---"
echo "--- First 1000 chars of Raw JSON: ---"
echo "${CURRENT_POLICY_JSON_RAW:0:1000}"
echo "--- Last 500 chars of Raw JSON: ---"
echo "${CURRENT_POLICY_JSON_RAW: -500}"
echo "--- END RAW DEBUG ---"

# Attempt to remove UTF-8 BOM and any leading characters before the first '{' or '['
# This is a best-effort cleaning for prefixes. It won't fix internal JSON corruption.
CLEANED_FOR_JQ=$(echo -n "${CURRENT_POLICY_JSON_RAW#$'\xEF\xBB\xBF'}" | sed -e 's/^\s*//' -e '1s/^[^{[]*//')

if [[ -z "$CLEANED_FOR_JQ" ]]; then
  echo "Error: After basic cleaning, the fetched IAM policy content is empty or does not appear to start with '{' or '['." >&2
  echo "This suggests the raw output from gcloud was not JSON or was severely malformed." >&2
  exit 1
fi

echo "--- DEBUG: JSON after basic prefix cleaning (before first jq parse; length: ${#CLEANED_FOR_JQ}) ---"
echo "--- First 1000 chars of Cleaned JSON: ---"
echo "${CLEANED_FOR_JQ:0:1000}"
echo "--- Last 500 chars of Cleaned JSON: ---"
echo "${CLEANED_FOR_JQ: -500}"
echo "--- END DEBUG ---"

echo "Strictly validating and parsing initially fetched (and cleaned) IAM policy with jq -e '.'..."
JQ_ERROR_LOG_FILE=$(mktemp)
# Use jq -e '.' for strict validation from the very beginning.
# The output of this (if successful) is the canonical, pretty-printed, and validated JSON.
TEMP_POLICY_VAR=$(jq -e '.' <<< "$CLEANED_FOR_JQ" 2> "$JQ_ERROR_LOG_FILE") # Use here-string
JQ_PARSE_EXIT_CODE=$?

if [[ $JQ_PARSE_EXIT_CODE -ne 0 ]]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
  echo "CRITICAL ERROR: The IAM policy fetched from GCP (after basic prefix cleaning) is NOT VALID JSON." >&2
  echo "JQ (strict mode -e) failed to parse it. JQ exit code: $JQ_PARSE_EXIT_CODE" >&2
  echo "JQ parsing errors reported:" >&2
  cat "$JQ_ERROR_LOG_FILE" >&2
  echo "This means the source IAM policy data from 'gcloud projects get-iam-policy' is likely corrupted" >&2
  echo "or contains structural errors (e.g., spaces in role names, missing commas, invalid syntax)" >&2
  echo "that the script's cleaning cannot fix. Please inspect the 'Cleaned JSON' debug output above." >&2
  echo "The script cannot proceed with a malformed source policy." >&2
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
  rm -f "$JQ_ERROR_LOG_FILE"; exit 1
fi

if [[ -z "$TEMP_POLICY_VAR" ]]; then
  echo "CRITICAL ERROR: Initial strict parsing of IAM policy with jq -e '.' succeeded but produced EMPTY output." >&2
  echo "This is unexpected and indicates a serious issue with the input or jq behavior." >&2
  echo "Cleaned JSON that resulted in empty output (first 1000 chars): ${CLEANED_FOR_JQ:0:1000}" >&2
  rm -f "$JQ_ERROR_LOG_FILE"; exit 1
fi

CURRENT_POLICY_JSON="$TEMP_POLICY_VAR"
echo "Current IAM policy initially fetched, cleaned, and STRICTLY parsed successfully."
MODIFIED_POLICY_JSON="$CURRENT_POLICY_JSON" # This is now known to be valid JSON.
rm -f "$JQ_ERROR_LOG_FILE"


add_or_update_member() {
  local policy_json_input="$1" # Should be valid JSON if initial parse was strict
  local role="$2"
  local member_type="$3"
  local member_email="$4" # Already cleaned from args
  local member_string="${member_type}:${member_email}"
  local temp_policy_json
  local jq_op_stderr_file

  echo "    --- Entering add_or_update_member for role '$role', member '$member_string' ---"
  jq_op_stderr_file=$(mktemp)

  # This initial validation inside add_or_update_member should now always pass
  # if the main script logic is correct because CURRENT_POLICY_JSON was strictly validated.
  # However, keeping it as a safeguard during development or if policy is passed incorrectly.
  if ! jq -e '.' <<< "$policy_json_input" >/dev/null 2>"$jq_op_stderr_file"; then
    echo "    FATAL ERROR (Sanity Check): Input JSON to add_or_update_member is not valid JSON." >&2
    echo "    This should NOT happen if initial strict parsing of CURRENT_POLICY_JSON was successful." >&2
    echo "    JQ validation error:" >&2; cat "$jq_op_stderr_file" >&2
    echo "    Problematic input (first 500 chars): '${policy_json_input:0:500}'"
    rm -f "$jq_op_stderr_file"; exit 1
  fi

  local role_exists_check
  # Using here-string for jq input
  role_exists_check=$(jq --arg role "$role" '.bindings[] | select(.role == $role)' <<< "$policy_json_input" 2> "$jq_op_stderr_file")
  # Check if jq command failed AND produced stderr output
  if [[ $? -ne 0 && $(wc -c < "$jq_op_stderr_file") -gt 0 ]]; then
      echo "    ERROR: jq failed to check for existing role binding for role '$role'." >&2; cat "$jq_op_stderr_file" >&2; rm -f "$jq_op_stderr_file"; exit 1
  fi

  if [[ -z "$role_exists_check" ]]; then
    # If the role binding does not exist, add a new binding for this role and member.
    echo "    Adding new binding for role '$role' with member '$member_string'."
    temp_policy_json=$(jq --arg role "$role" --arg member "$member_string" '
      .bindings += [{
        "role": $role,
        "members": [$member]
        # Condition is explicitly omitted
      }]
    ' <<< "$policy_json_input" 2> "$jq_op_stderr_file")
  else
    # If the role binding exists, check if the member is already part of this binding.
    local member_in_role_check
    member_in_role_check=$(jq --arg role "$role" --arg member "$member_string" '
      .bindings[] | select(.role == $role) | .members[] | select(. == $member)
    ' <<< "$policy_json_input" 2> "$jq_op_stderr_file")
    if [[ $? -ne 0 && $(wc -c < "$jq_op_stderr_file") -gt 0 ]]; then
      echo "    ERROR: jq failed to check for existing member in role '$role'." >&2; cat "$jq_op_stderr_file" >&2; rm -f "$jq_op_stderr_file"; exit 1
    fi

    if [[ -z "$member_in_role_check" ]]; then
      # If the member is not in the existing role binding, add them.
      echo "    Adding member '$member_string' to existing role '$role'."
      temp_policy_json=$(jq --arg role "$role" --arg member "$member_string" '
        (.bindings[] | select(.role == $role).members) |= (. + [$member] | unique)
      ' <<< "$policy_json_input" 2> "$jq_op_stderr_file")
    else
      echo "    Member '$member_string' already exists in role '$role'. Skipping."
      temp_policy_json="$policy_json_input" # No change, so keep original
    fi
  fi

  # Universal check for jq operation success and output validity
  if [[ $? -ne 0 ]]; then # Check exit status of the last jq command that set temp_policy_json
    echo "    ERROR: JQ operation for role '$role' failed (exit status $?)." >&2; cat "$jq_op_stderr_file" >&2; rm -f "$jq_op_stderr_file"; exit 1
  fi
  # Check for empty output only if a change was actually attempted and policy_json_input was not already equal to temp_policy_json
  if [[ -z "$temp_policy_json" && "$policy_json_input" != "$temp_policy_json" ]]; then
      echo "    ERROR: JQ operation for role '$role' produced empty output when a change was expected." >&2; cat "$jq_op_stderr_file" >&2; rm -f "$jq_op_stderr_file"; exit 1
  fi
  # Final validation of the modified JSON
  if ! jq -e '.' <<< "$temp_policy_json" >/dev/null 2>>"$jq_op_stderr_file"; then # Append to same log for context
      echo "    CRITICAL ERROR: JQ operation resulted in invalid JSON output for role '$role'." >&2
      echo "    Faulty JSON (first 500): '${temp_policy_json:0:500}'" >&2
      echo "    Cumulative JQ errors for this member/role:" >&2; cat "$jq_op_stderr_file" >&2
      rm -f "$jq_op_stderr_file"; exit 1
  fi

  rm -f "$jq_op_stderr_file"
  echo "    --- Exiting add_or_update_member (role: '$role') with valid JSON ---"
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
    "CUSTOM_BUNDLE_1") # Example from before
      roles="roles/compute.admin,roles/container.admin"
      ;;
    # --- NEW BUNDLED ROLES ---
    "GenAIUser") # Corrected from "GenAluser"
      roles="roles/artifactregistry.admin,roles/aiplatform.user,roles/notebooks.admin,roles/storage.admin,roles/bigquery.dataEditor,roles/bigquery.jobUser,roles/dlp.admin"
      ;;
    "GenAIViewer") # Corrected role names
      roles="roles/aiplatform.viewer,roles/bigquery.dataViewer,roles/storage.objectViewer,roles/notebooks.viewer,roles/dlp.jobsReader"
      ;;
    "GenAIFeatureStoreUser") # Corrected from "GenAIfeaturestoreuser" and role name
      roles="roles/aiplatform.featurestoreUser"
      ;;
    "GenAIFeatureStoreViewer") # Corrected from "GenAIfeaturestoreviewer"
      roles="roles/aiplatform.featurestoreDataViewer,roles/aiplatform.featurestoreResourceViewer"
      ;;
    "GenAppBuilderUser")
      roles="roles/discoveryengine.editor"
      ;;
    # --- END NEW BUNDLED ROLES ---
    *)
      echo "Error: Unknown bundled role name: '$bundle_name'. Please check the script's 'get_bundled_roles' function and the GitHub workflow inputs." >&2
      exit 1
      ;;
  esac
  echo "$roles"
}

# --- Process Roles based on TARGET_TYPE ---
# (This section remains largely the same as it calls add_or_update_member)
if [[ "$TARGET_TYPE" == "service_account" ]]; then
  ALL_SA_ROLES=""
  if [[ -n "$IAM_ROLES_SA" ]]; then ALL_SA_ROLES="$IAM_ROLES_SA"; fi
  if [[ -n "$BUNDLED_ROLES_SA" ]]; then
    BUNDLED_ROLES_RESOLVED=$(get_bundled_roles "$BUNDLED_ROLES_SA")
    if [[ -n "$ALL_SA_ROLES" ]]; then ALL_SA_ROLES="${ALL_SA_ROLES},${BUNDLED_ROLES_RESOLVED}"; else ALL_SA_ROLES="$BUNDLED_ROLES_RESOLVED"; fi
  fi
  if [[ -n "$ALL_SA_ROLES" ]]; then
    echo "Processing roles for Service Account: $GCP_SERVICE_ACCOUNT_EMAIL"
    IFS=',' read -ra SA_ROLES_ARRAY <<< "$ALL_SA_ROLES"
    for role in "${SA_ROLES_ARRAY[@]}"; do
      role_trimmed=$(echo "$role" | xargs); if [[ -n "$role_trimmed" ]]; then MODIFIED_POLICY_JSON=$(add_or_update_member "$MODIFIED_POLICY_JSON" "$role_trimmed" "serviceAccount" "$GCP_SERVICE_ACCOUNT_EMAIL"); fi
    done
  else echo "No roles specified for Service Account. Skipping."; fi
elif [[ "$TARGET_TYPE" == "ad_group" ]]; then
  ALL_AD_ROLES=""
  if [[ -n "$IAM_ROLES_AD" ]]; then ALL_AD_ROLES="$IAM_ROLES_AD"; fi
  if [[ -n "$BUNDLED_ROLES_AD" ]]; then
    BUNDLED_ROLES_RESOLVED=$(get_bundled_roles "$BUNDLED_ROLES_AD")
    if [[ -n "$ALL_AD_ROLES" ]]; then ALL_AD_ROLES="${ALL_AD_ROLES},${BUNDLED_ROLES_RESOLVED}"; else ALL_AD_ROLES="$BUNDLED_ROLES_RESOLVED"; fi
  fi
  if [[ -n "$ALL_AD_ROLES" ]]; then
    echo "Processing roles for AD Group: $AD_GROUP_EMAIL"
    IFS=',' read -ra AD_ROLES_ARRAY <<< "$ALL_AD_ROLES"
    for role in "${AD_ROLES_ARRAY[@]}"; do
      role_trimmed=$(echo "$role" | xargs); if [[ -n "$role_trimmed" ]]; then MODIFIED_POLICY_JSON=$(add_or_update_member "$MODIFIED_POLICY_JSON" "$role_trimmed" "group" "$AD_GROUP_EMAIL"); fi
    done
  else echo "No roles specified for AD Group. Skipping."; fi
fi


# --- Dry Run vs. Apply ---
# (This section remains largely the same, assumes MODIFIED_POLICY_JSON is valid)
JQ_FINAL_OUTPUT_STDERR_FILE=$(mktemp)
if [[ "$MODE" == "dry-run" ]]; then
  echo "--- Dry Run Output (Proposed IAM Policy) ---"
  # Output to stdout for the GitHub Action to capture
  jq . <<< "$MODIFIED_POLICY_JSON" > /dev/stdout 2> "$JQ_FINAL_OUTPUT_STDERR_FILE" || {
    echo "Error: jq failed to format final dry-run policy." >&2
    cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2
    rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"
    exit 1;
  }
  if [[ -s "$JQ_FINAL_OUTPUT_STDERR_FILE" ]]; then # Check if stderr file has size > 0
      echo "Warning: jq produced stderr during final dry-run formatting:" >&2
      cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2
  fi
  echo "--- End Dry Run Output ---"
  echo "Dry run successful: Proposed changes are displayed. No changes applied to GCP."
elif [[ "$MODE" == "apply" ]]; then
  echo "Applying modified IAM policy to project $GCP_PROJECT_ID..."
  # Extract the ETag from the original policy. This is crucial for optimistic concurrency.
  ETAG=$(jq -r '.etag' <<< "$CURRENT_POLICY_JSON" 2> "$JQ_FINAL_OUTPUT_STDERR_FILE")
  if [[ $? -ne 0 || -z "$ETAG" || "$ETAG" == "null" ]]; then
    echo "Error: Failed to extract ETag from current policy, or ETag is empty/null." >&2
    cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2
    rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"
    exit 1
  fi
  
  # Add the ETag to the modified policy JSON before applying it.
  FINAL_POLICY_TO_APPLY=$(jq --arg etag "$ETAG" '.etag = $etag' <<< "$MODIFIED_POLICY_JSON" 2> "$JQ_FINAL_OUTPUT_STDERR_FILE")
  if [[ $? -ne 0 || -z "$FINAL_POLICY_TO_APPLY" ]]; then
    echo "Error: Failed to inject ETag into the modified policy or result was empty." >&2
    cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2
    rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"
    exit 1
  fi
  
  echo "--- DEBUG: Final policy to apply (with ETag) ---"
  jq . <<< "$FINAL_POLICY_TO_APPLY" # For debugging
  echo "--- END DEBUG ---"

  GCLOUD_SET_POLICY_STDERR_FILE=$(mktemp)
  APPLY_RESULT_JSON_FILE=$(mktemp)

  # Apply the policy using gcloud. We pipe the JSON directly to stdin.
  if ! gcloud projects set-iam-policy "$GCP_PROJECT_ID" /dev/stdin --format=json --quiet <<< "$FINAL_POLICY_TO_APPLY" > "$APPLY_RESULT_JSON_FILE" 2> "$GCLOUD_SET_POLICY_STDERR_FILE"; then
    echo "Error: 'gcloud projects set-iam-policy' command failed to apply the new policy." >&2
    echo "Gcloud Stderr:" >&2; cat "$GCLOUD_SET_POLICY_STDERR_FILE" >&2
    echo "Gcloud Stdout (if any):" >&2; cat "$APPLY_RESULT_JSON_FILE" >&2 # gcloud might output error structure to stdout
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

  echo "IAM policy applied successfully. New policy after application:"
  jq . <<< "$APPLY_RESULT" > /dev/stdout 2> "$JQ_FINAL_OUTPUT_STDERR_FILE" || {
    echo "Error: jq failed to format the policy returned by 'set-iam-policy'." >&2
    echo "Raw output from gcloud was:" >&2; echo "$APPLY_RESULT" >&2
    cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2
    # Don't exit here as policy was applied, but formatting failed.
  }
fi
rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE" # Clean up if it exists
echo "--- Script Finished ---"

