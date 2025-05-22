#!/bin/bash

# This script deletes a Vertex AI Notebook instance.
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
# NOTEBOOK_NAME
# ZONE

# Validate required environment variables
if [ -z "$SERVICE_PROJECT_ID" ] || \
   [ -z "$NOTEBOOK_NAME" ] || \
   [ -z "$ZONE" ]; then
  echo "Error: One or more required environment variables are not set."
  echo "Required: SERVICE_PROJECT_ID, NOTEBOOK_NAME, ZONE"
  exit 1
fi

echo "--- Inputs Received ---"
echo "SERVICE_PROJECT_ID: $SERVICE_PROJECT_ID"
echo "NOTEBOOK_NAME: $NOTEBOOK_NAME"
echo "ZONE: $ZONE"
echo "MODE: $MODE"
echo "-----------------------"

# --- Execute gcloud commands based on MODE ---
if [ "$MODE" == "--dry-run" ]; then
  echo "--- Performing Dry Run for Vertex AI Notebook Deletion ---"
  # Check if Vertex AI Notebook instance exists before dry-running deletion
  if gcloud workbench instances describe "${NOTEBOOK_NAME}" --project="${SERVICE_PROJECT_ID}" --location="${ZONE}" &> /dev/null; then
    echo "Vertex AI Notebook instance '${NOTEBOOK_NAME}' found in zone '${ZONE}'. Simulating deletion."
    # For dry-run of destructive commands, it's safest to just echo the command.
    echo "Simulating: gcloud workbench instances delete \"${NOTEBOOK_NAME}\" --project=\"${SERVICE_PROJECT_ID}\" --location=\"${ZONE}\" --quiet"
  else
    echo "Vertex AI Notebook instance '${NOTEBOOK_NAME}' not found in zone '${ZONE}'. Skipping dry run for deletion as it does not exist."
  fi

elif [ "$MODE" == "--apply" ]; then
  echo "--- Applying Vertex AI Notebook Deletion ---"
  # Check if Vertex AI Notebook instance exists before applying deletion
  if gcloud workbench instances describe "${NOTEBOOK_NAME}" --project="${SERVICE_PROJECT_ID}" --location="${ZONE}" &> /dev/null; then
    echo "Vertex AI Notebook instance '${NOTEBOOK_NAME}' found in zone '${ZONE}'. Proceeding with deletion."
    echo "Executing Vertex AI Notebook deletion command: gcloud workbench instances delete \"${NOTEBOOK_NAME}\" --project=\"${SERVICE_PROJECT_ID}\" --location=\"${ZONE}\" --quiet"
    gcloud workbench instances delete "${NOTEBOOK_NAME}" \
      --project="${SERVICE_PROJECT_ID}" \
      --location="${ZONE}" \
      --quiet # Add --quiet for non-interactive deletion
  else
    echo "Vertex AI Notebook instance '${NOTEBOOK_NAME}' not found in zone '${ZONE}'. Skipping deletion."
  fi

else
  echo "Error: Invalid mode. Use '--dry-run' or '--apply'."
  exit 1
fi

echo "Script execution complete."
