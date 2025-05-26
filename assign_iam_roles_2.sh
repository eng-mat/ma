#!/bin/bash
set -euo pipefail

# assign_iam_roles.sh
# This script is a wrapper that parses arguments and calls the Python IAM assignment script.

# --- Configuration and Argument Parsing ---

MODE=""
GCP_PROJECT_ID=""
TARGET_TYPE=""
GCP_SERVICE_ACCOUNT_EMAIL=""
AD_GROUP_EMAIL=""
IAM_ROLES_RAW="" # Individual roles provided directly
BUNDLED_ROLES_RAW="" # Bundled roles provided directly

# Python script path relative to this wrapper script
PYTHON_SCRIPT="./assign_iam_roles.py"

# Function to display usage information
usage() {
  echo "Usage: $0 --mode <dry-run|apply> --project-id <GCP_PROJECT_ID> \\"
  echo "          --target-type <service_account|ad_group> \\"
  echo "          [--service-account-email <SA_EMAIL>] [--ad-group-email <AD_GROUP_EMAIL>] \\"
  echo "          [--roles <ROLE1,ROLE2>] \\"
  echo "          [--bundled-roles <BUNDLE_NAME>]"
  echo ""
  echo "Arguments:"
  echo "  --mode                      : Operation mode: 'dry-run' (show changes) or 'apply' (implement changes)."
  echo "  --project-id                : The GCP Project ID."
  echo "  --target-type               : The type of principal to assign roles to: 'service_account' or 'ad_group'."
  echo "  --service-account-email : (Required if --target-type is 'service_account') The email of the GCP Service Account."
  echo "  --ad-group-email          : (Required if --target-type is 'ad_group') The email of the Active Directory Group (must be synced to GCP)."
  echo "  --roles                     : (Optional) Comma-separated individual IAM roles."
  echo "  --bundled-roles             : (Optional) Name of a predefined bundled role (e.g., 'GenAIUser', 'GenAppBuilderUser')."
  echo ""
  echo "Note: At least one of --roles or --bundled-roles must be provided."
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
      # Clean input email: remove leading/trailing whitespace and trailing asterisk if present
      GCP_SERVICE_ACCOUNT_EMAIL=$(echo "$2" | xargs | sed 's/\*$//g')
      shift
      ;;
    --ad-group-email)
      # Clean input email: remove leading/trailing whitespace and trailing asterisk if present
      AD_GROUP_EMAIL=$(echo "$2" | xargs | sed 's/\*$//g')
      shift
      ;;
    --roles)
      IAM_ROLES_RAW="$2"
      shift
      ;;
    --bundled-roles)
      BUNDLED_ROLES_RAW="$2"
      shift
      ;;
    *)
      echo "Unknown parameter: $1" >&2
      usage
      ;;
  esac
  shift
done

# --- Validate required arguments ---
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
elif [[ "$TARGET_TYPE" == "ad_group" ]]; then
  if [[ -z "$AD_GROUP_EMAIL" ]]; then
    echo "Error: --ad-group-email is required when --target-type is 'ad_group'." >&2
    usage
  fi
fi

if [[ -z "$IAM_ROLES_RAW" && -z "$BUNDLED_ROLES_RAW" ]]; then
  echo "Error: At least one of --roles or --bundled-roles must be provided." >&2
  usage
fi

echo "Script arguments validated successfully."

echo "--- Starting IAM Role Assignment Script ($MODE mode) ---"
echo "Project ID: $GCP_PROJECT_ID"
echo "Target Type: $TARGET_TYPE"
if [[ "$TARGET_TYPE" == "service_account" ]]; then
  echo "Service Account: $GCP_SERVICE_ACCOUNT_EMAIL"
  echo "Individual Roles: ${IAM_ROLES_RAW:-None}"
  echo "Bundled Role: ${BUNDLED_ROLES_RAW:-None}"
elif [[ "$TARGET_TYPE" == "ad_group" ]]; then
  echo "AD Group: $AD_GROUP_EMAIL"
  echo "Individual Roles: ${IAM_ROLES_RAW:-None}"
  echo "Bundled Role: ${BUNDLED_ROLES_RAW:-None}"
fi
echo "------------------------------------------------------"

# --- Pre-checks ---

# Check for gcloud CLI tool
if ! command -v gcloud &> /dev/null; then
  echo "Error: gcloud CLI not found. Please ensure it's installed and in your PATH." >&2
  exit 1
fi

# Check for python3
if ! command -v python3 &> /dev/null; then
  echo "Error: python3 not found. Please ensure it's installed and in your PATH." >&2
  exit 1
fi

# Check if the Python script exists
if [[ ! -f "$PYTHON_SCRIPT" ]]; then
  echo "Error: Python script '$PYTHON_SCRIPT' not found. Please ensure it's in the same directory as this wrapper." >&2
  exit 1
fi

echo "Setting gcloud project to $GCP_PROJECT_ID..."
gcloud config set project "$GCP_PROJECT_ID" --quiet 2> >(tee /dev/stderr) || { echo "Error: Failed to set gcloud project context. This might indicate an invalid Project ID: '$GCP_PROJECT_ID'." >&2; exit 1; }
echo "Gcloud project set to $GCP_PROJECT_ID."

# --- Call Python Script ---
PYTHON_ARGS=(
  "--mode" "$MODE"
  "--project-id" "$GCP_PROJECT_ID"
  "--target-type" "$TARGET_TYPE"
)

if [[ "$TARGET_TYPE" == "service_account" ]]; then
  PYTHON_ARGS+=("--service-account-email" "$GCP_SERVICE_ACCOUNT_EMAIL")
elif [[ "$TARGET_TYPE" == "ad_group" ]]; then
  PYTHON_ARGS+=("--ad-group-email" "$AD_GROUP_EMAIL")
fi

if [[ -n "$IAM_ROLES_RAW" ]]; then
  PYTHON_ARGS+=("--roles" "$IAM_ROLES_RAW")
fi
if [[ -n "$BUNDLED_ROLES_RAW" ]]; then
  PYTHON_ARGS+=("--bundled-roles" "$BUNDLED_ROLES_RAW")
fi

echo "Invoking Python script: python3 $PYTHON_SCRIPT ${PYTHON_ARGS[@]}"
python3 "$PYTHON_SCRIPT" "${PYTHON_ARGS[@]}"

# Capture Python script's exit code
PYTHON_EXIT_CODE=$?

if [[ $PYTHON_EXIT_CODE -ne 0 ]]; then
  echo "Error: Python script failed with exit code $PYTHON_EXIT_CODE." >&2
  exit $PYTHON_EXIT_CODE
fi

echo "--- Script Finished Successfully ---"
