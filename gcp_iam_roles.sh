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
  # ... (rest of usage message remains the same)
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
      # Trim whitespace and remove trailing asterisk if present
      GCP_SERVICE_ACCOUNT_EMAIL=$(echo "$2" | xargs | sed 's/\*$//g')
      shift ;;
    --ad-group-email)
      AD_GROUP_EMAIL=$(echo "$2" | xargs | sed 's/\*$//g')
      shift ;;
    --roles-sa) IAM_ROLES_SA="$2"; shift ;;
    --roles-ad) IAM_ROLES_AD="$2"; shift ;;
    --bundled-roles-sa) BUNDLED_ROLES_SA="$2"; shift ;;
    --bundled-roles-ad) BUNDLED_ROLES_AD="$2"; shift ;;
    *) echo "Unknown parameter: $1" >&2; usage ;;
  esac
  shift
done

# --- Validate required arguments (remains the same) ---
echo "Validating script arguments..."
if [[ -z "$MODE" || -z "$GCP_PROJECT_ID" || -z "$TARGET_TYPE" ]]; then
  echo "Error: --mode, --project-id, and --target-type are required." >&2; usage
fi
if [[ "$MODE" != "dry-run" && "$MODE" != "apply" ]]; then
  echo "Error: --mode must be 'dry-run' or 'apply'." >&2; usage
fi
if [[ "$TARGET_TYPE" != "service_account" && "$TARGET_TYPE" != "ad_group" ]]; then
  echo "Error: --target-type must be 'service_account' or 'ad_group'." >&2; usage
fi
if [[ "$TARGET_TYPE" == "service_account" ]]; then
  if [[ -z "$GCP_SERVICE_ACCOUNT_EMAIL" ]]; then
    echo "Error: --service-account-email is required when --target-type is 'service_account'." >&2; usage
  fi
  if [[ -z "$IAM_ROLES_SA" && -z "$BUNDLED_ROLES_SA" ]]; then
    echo "Error: At least one of --roles-sa or --bundled-roles-sa must be provided for the Service Account." >&2; usage
  fi
elif [[ "$TARGET_TYPE" == "ad_group" ]]; then
  if [[ -z "$AD_GROUP_EMAIL" ]]; then
    echo "Error: --ad-group-email is required when --target-type is 'ad_group'." >&2; usage
  fi
  if [[ -z "$IAM_ROLES_AD" && -z "$BUNDLED_ROLES_AD" ]]; then
    echo "Error: At least one of --roles-ad or --bundled-roles-ad must be provided for the AD Group." >&2; usage
  fi
fi
echo "Script arguments validated successfully."
echo "Service Account Email after cleaning: '$GCP_SERVICE_ACCOUNT_EMAIL'" # Debug
echo "AD Group Email after cleaning: '$AD_GROUP_EMAIL'" # Debug


# --- Info print (remains the same) ---
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


# --- Pre-checks and Setup (remains mostly the same) ---
if ! command -v gcloud &> /dev/null; then echo "Error: gcloud CLI not found." >&2; exit 1; fi
if ! command -v jq &> /dev/null; then echo "Error: jq not found." >&2; exit 1; fi

echo "Setting gcloud project to $GCP_PROJECT_ID..."
# (gcloud config set project ... logic remains the same)
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
# (gcloud projects get-iam-policy ... logic remains the same)
GCLOUD_GET_POLICY_STDOUT_FILE=$(mktemp)
GCLOUD_GET_POLICY_STDERR_FILE=$(mktemp)
if ! gcloud projects get-iam-policy "$GCP_PROJECT_ID" --format=json --quiet > "$GCLOUD_GET_POLICY_STDOUT_FILE" 2> "$GCLOUD_GET_POLICY_STDERR_FILE"; then
    echo "Error: 'gcloud projects get-iam-policy \"$GCP_PROJECT_ID\" --format=json' command failed." >&2; cat "$GCLOUD_GET_POLICY_STDERR_FILE" >&2; cat "$GCLOUD_GET_POLICY_STDOUT_FILE" >&2; rm -f "$GCLOUD_GET_POLICY_STDOUT_FILE" "$GCLOUD_GET_POLICY_STDERR_FILE"; exit 1
fi
GCLOUD_GET_POLICY_STDERR_CONTENT=$(cat "$GCLOUD_GET_POLICY_STDERR_FILE")
if [[ -n "$GCLOUD_GET_POLICY_STDERR_CONTENT" ]]; then echo "Stderr from 'gcloud projects get-iam-policy':" >&2; echo "$GCLOUD_GET_POLICY_STDERR_CONTENT" >&2; fi
CURRENT_POLICY_JSON_RAW=$(cat "$GCLOUD_GET_POLICY_STDOUT_FILE")
rm -f "$GCLOUD_GET_POLICY_STDOUT_FILE" "$GCLOUD_GET_POLICY_STDERR_FILE"

if [[ -z "$CURRENT_POLICY_JSON_RAW" ]]; then echo "Error: Fetched IAM policy for project '$GCP_PROJECT_ID' is empty." >&2; exit 1; fi

echo "--- DEBUG: Raw JSON fetched from gcloud (length: ${#CURRENT_POLICY_JSON_RAW}) ---"
# echo "$CURRENT_POLICY_JSON_RAW" # Can be very verbose
echo "--- First 1000 chars of Raw JSON: ---"
echo "${CURRENT_POLICY_JSON_RAW:0:1000}"
echo "--- END RAW DEBUG ---"

# Aggressively clean: remove UTF-8 BOM, then strip anything before the first '{' or '['.
# This helps if gcloud output has any prefix.
CLEANED_FOR_JQ=$(echo -n "${CURRENT_POLICY_JSON_RAW#$'\xEF\xBB\xBF'}" | sed -e 's/^\s*//' -e '1s/^[^{[]*//')

if [[ -z "$CLEANED_FOR_JQ" ]]; then
  echo "Error: After attempting to clean/trim, the fetched IAM policy is empty or not starting with '{' or '['." >&2
  echo "Original raw content started with (first 200 chars): ${CURRENT_POLICY_JSON_RAW:0:200}" >&2
  exit 1
fi

echo "--- DEBUG: JSON after basic cleaning (before first jq parse; length: ${#CLEANED_FOR_JQ}) ---"
# echo "$CLEANED_FOR_JQ" # Can be verbose
echo "--- First 1000 chars of Cleaned JSON: ---"
echo "${CLEANED_FOR_JQ:0:1000}"
echo "--- END DEBUG ---"

echo "Validating and parsing fetched IAM policy with jq..."
JQ_ERROR_LOG_FILE=$(mktemp)
CURRENT_POLICY_JSON=$(echo "$CLEANED_FOR_JQ" | jq '.' 2> "$JQ_ERROR_LOG_FILE")
JQ_PARSE_EXIT_CODE=$?
if [[ $JQ_PARSE_EXIT_CODE -ne 0 ]]; then
  echo "ERROR: Failed to parse the IAM policy JSON (after cleaning) for project '$GCP_PROJECT_ID'." >&2; echo "JQ exit code: $JQ_PARSE_EXIT_CODE" >&2; echo "JQ parsing errors:" >&2; cat "$JQ_ERROR_LOG_FILE" >&2
  echo "The cleaned JSON input provided to JQ started with (first 200 chars): ${CLEANED_FOR_JQ:0:200}" >&2
  rm -f "$JQ_ERROR_LOG_FILE"; exit 1
fi
rm -f "$JQ_ERROR_LOG_FILE"
echo "Current IAM policy fetched and parsed successfully."
MODIFIED_POLICY_JSON="$CURRENT_POLICY_JSON"

add_or_update_member() {
  local policy_json_input="$1"
  local role="$2"
  local member_type="$3"
  local member_email="$4" # Already cleaned from args
  local member_string="${member_type}:${member_email}"
  local temp_policy_json
  local jq_op_stderr_file

  echo "    --- Entering add_or_update_member for role '$role', member '$member_string' ---"
  jq_op_stderr_file=$(mktemp)

  # Validate input JSON before proceeding
  echo "    DEBUG: Validating policy_json_input in add_or_update_member (length: ${#policy_json_input}, first 500 chars): '${policy_json_input:0:500}'"
  if ! echo "$policy_json_input" | jq -e '.' >/dev/null 2>"$jq_op_stderr_file"; then
    echo "    FATAL ERROR: Input JSON to add_or_update_member is not valid JSON." >&2
    echo "    JQ validation error:" >&2; cat "$jq_op_stderr_file" >&2
    rm -f "$jq_op_stderr_file"; exit 1
  fi

  local role_exists_check
  role_exists_check=$(echo "$policy_json_input" | jq --arg role "$role" '.bindings[] | select(.role == $role)' 2> "$jq_op_stderr_file")
  if [[ $? -ne 0 && $(cat "$jq_op_stderr_file" | wc -c) -gt 0 ]]; then
      echo "    ERROR: jq failed to check for existing role binding for role '$role'." >&2; cat "$jq_op_stderr_file" >&2; rm -f "$jq_op_stderr_file"; exit 1
  fi

  if [[ -z "$role_exists_check" ]]; then
    echo "    Adding new binding for role '$role' with member '$member_string'."
    temp_policy_json=$(echo "$policy_json_input" | jq --arg role "$role" --arg member "$member_string" '.bindings += [{"role": $role, "members": [$member]}]' 2> "$jq_op_stderr_file")
  else
    local member_in_role_check
    member_in_role_check=$(echo "$policy_json_input" | jq --arg role "$role" --arg member "$member_string" '.bindings[] | select(.role == $role) | .members[] | select(. == $member)' 2> "$jq_op_stderr_file")
    if [[ $? -ne 0 && $(cat "$jq_op_stderr_file" | wc -c) -gt 0 ]]; then
      echo "    ERROR: jq failed to check for existing member in role '$role'." >&2; cat "$jq_op_stderr_file" >&2; rm -f "$jq_op_stderr_file"; exit 1
    fi
    if [[ -z "$member_in_role_check" ]]; then
      echo "    Adding member '$member_string' to existing role '$role'."
      temp_policy_json=$(echo "$policy_json_input" | jq --arg role "$role" --arg member "$member_string" '(.bindings[] | select(.role == $role).members) |= (. + [$member] | unique)') # Simpler update
    else
      echo "    Member '$member_string' already exists in role '$role'. Skipping."
      temp_policy_json="$policy_json_input" # No change
    fi
  fi

  # Universal check for jq operation success and output validity
  if [[ $? -ne 0 || -z "$temp_policy_json" ]]; then
    echo "    ERROR: Previous jq operation failed or produced empty output for role '$role'." >&2; cat "$jq_op_stderr_file" >&2; rm -f "$jq_op_stderr_file"; exit 1
  fi
  if ! echo "$temp_policy_json" | jq -e '.' >/dev/null 2>>"$jq_op_stderr_file"; then # Append to same log for context
      echo "    CRITICAL ERROR: jq operation produced invalid JSON output for role '$role'." >&2; echo "    Faulty JSON (first 500): '${temp_policy_json:0:500}'" >&2; cat "$jq_op_stderr_file" >&2; rm -f "$jq_op_stderr_file"; exit 1
  fi

  rm -f "$jq_op_stderr_file"
  echo "    --- Exiting add_or_update_member (role: '$role') ---"
  echo "$temp_policy_json"
}

# --- Function to resolve bundled roles (remains the same) ---
get_bundled_roles() {
  local bundle_name="$1"; local roles=""
  case "$bundle_name" in
    "GenAI_ADMIN") roles="roles/aiplatform.admin,roles/aiplatform.user,roles/notebooks.admin,roles/storage.admin,roles/bigquery.admin" ;;
    "GenAI_DEVELOPER") roles="roles/aiplatform.user,roles/viewer,roles/bigquery.dataViewer,roles/storage.objectViewer" ;;
    "CUSTOM_BUNDLE_1") roles="roles/compute.admin,roles/container.admin" ;;
    *) echo "Error: Unknown bundled role name: '$bundle_name'." >&2; exit 1 ;;
  esac
  echo "$roles"
}

# --- Process Roles based on TARGET_TYPE (remains the same, relies on add_or_update_member) ---
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

# --- Dry Run vs. Apply (remains mostly the same, relies on MODIFIED_POLICY_JSON being valid) ---
JQ_FINAL_OUTPUT_STDERR_FILE=$(mktemp)
if [[ "$MODE" == "dry-run" ]]; then
  echo "--- Dry Run Output (Proposed IAM Policy) ---"
  echo "$MODIFIED_POLICY_JSON" | jq . 2> "$JQ_FINAL_OUTPUT_STDERR_FILE" || { echo "Error: jq failed to format final dry-run policy." >&2; cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2; rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"; exit 1; }
  if [[ -s "$JQ_FINAL_OUTPUT_STDERR_FILE" ]]; then echo "Warning: jq produced stderr during final dry-run formatting:" >&2; cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2; fi
  echo "--- End Dry Run Output ---"; echo "Validation successful: Proposed changes are displayed. No changes applied."
elif [[ "$MODE" == "apply" ]]; then
  echo "Applying modified IAM policy to project $GCP_PROJECT_ID..."
  ETAG=$(echo "$CURRENT_POLICY_JSON" | jq -r '.etag' 2> "$JQ_FINAL_OUTPUT_STDERR_FILE")
  if [[ $? -ne 0 || -z "$ETAG" || "$ETAG" == "null" ]]; then echo "Error: Failed to extract ETag, or ETag is empty/null." >&2; cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2; rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"; exit 1; fi
  FINAL_POLICY_TO_APPLY=$(echo "$MODIFIED_POLICY_JSON" | jq --arg etag "$ETAG" '.etag = $etag' 2> "$JQ_FINAL_OUTPUT_STDERR_FILE")
  if [[ $? -ne 0 || -z "$FINAL_POLICY_TO_APPLY" ]]; then echo "Error: Failed to inject ETag or result was empty." >&2; cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2; rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"; exit 1; fi
  # (gcloud projects set-iam-policy ... logic remains the same)
  GCLOUD_SET_POLICY_STDERR_FILE=$(mktemp); APPLY_RESULT_JSON_FILE=$(mktemp)
  if ! echo "$FINAL_POLICY_TO_APPLY" | gcloud projects set-iam-policy "$GCP_PROJECT_ID" /dev/stdin --format=json --quiet > "$APPLY_RESULT_JSON_FILE" 2> "$GCLOUD_SET_POLICY_STDERR_FILE"; then
    echo "Error: 'gcloud projects set-iam-policy' command failed." >&2; cat "$GCLOUD_SET_POLICY_STDERR_FILE" >&2; cat "$APPLY_RESULT_JSON_FILE" >&2; rm -f "$GCLOUD_SET_POLICY_STDERR_FILE" "$APPLY_RESULT_JSON_FILE" "$JQ_FINAL_OUTPUT_STDERR_FILE"; exit 1
  fi
  GCLOUD_SET_POLICY_STDERR_CONTENT=$(cat "$GCLOUD_SET_POLICY_STDERR_FILE")
  if [[ -n "$GCLOUD_SET_POLICY_STDERR_CONTENT" ]]; then echo "Warning: 'gcloud projects set-iam-policy' produced stderr:" >&2; echo "$GCLOUD_SET_POLICY_STDERR_CONTENT" >&2; fi
  APPLY_RESULT=$(cat "$APPLY_RESULT_JSON_FILE"); rm -f "$GCLOUD_SET_POLICY_STDERR_FILE" "$APPLY_RESULT_JSON_FILE"
  echo "IAM policy applied successfully. New policy:"; echo "$APPLY_RESULT" | jq . 2> "$JQ_FINAL_OUTPUT_STDERR_FILE" || { echo "Error: jq failed to format applied policy." >&2; echo "Raw: $APPLY_RESULT" >&2; cat "$JQ_FINAL_OUTPUT_STDERR_FILE" >&2; }
fi
rm -f "$JQ_FINAL_OUTPUT_STDERR_FILE"
echo "--- Script Finished ---"
