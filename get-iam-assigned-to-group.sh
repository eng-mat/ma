# Sample file filename.txt
#my-project-1 ad-group-alpha@example.com
#dev-project-2 ad-group-beta@example.com

# chmod +x get_iam_roles.sh
# ./get_iam_roles.sh



#!/bin/bash

# File containing project to AD group mappings (e.g., project-id ad-group@yourdomain.com)
MAPPING_FILE="project_group_mapping.txt"

# Output file for logging (optional)
LOG_FILE="iam_roles_report.log"

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

log_message "Starting IAM Roles Report Generation..."
log_message "----------------------------------------------------"

# Check if the mapping file exists
if [[ ! -f "$MAPPING_FILE" ]]; then
    log_message "ERROR: Mapping file '$MAPPING_FILE' not found. Please create it with project ID and AD group mappings."
    exit 1
fi

while IFS=" " read -r PROJECT_ID AD_GROUP_EMAIL; do
    if [[ -z "$PROJECT_ID" || -z "$AD_GROUP_EMAIL" ]]; then
        log_message "WARNING: Skipping empty or malformed line in mapping file: '$PROJECT_ID $AD_GROUP_EMAIL'"
        continue
    fi

    log_message "Processing Project: $PROJECT_ID"
    log_message "Mapped AD Group: $AD_GROUP_EMAIL"

    # 1. Check if the project exists
    PROJECT_EXISTS=$(gcloud projects describe "$PROJECT_ID" --format="value(projectId)" 2>/dev/null)

    if [[ -z "$PROJECT_EXISTS" ]]; then
        log_message "NOTE: Project '$PROJECT_ID' not found or decommissioned. Skipping this project."
        log_message "----------------------------------------------------"
        continue
    fi

    log_message "Project '$PROJECT_ID' found."

    # 2. Get IAM roles for the AD Group
    log_message "Fetching IAM roles for AD Group '$AD_GROUP_EMAIL' in project '$PROJECT_ID'..."
    AD_GROUP_ROLES=$(gcloud projects get-iam-policy "$PROJECT_ID" \
        --flatten="bindings[].members" \
        --format="table(bindings.role,bindings.members)" \
        --filter="bindings.members:'group:$AD_GROUP_EMAIL'" 2>/dev/null)

    if [[ -z "$AD_GROUP_ROLES" || "$AD_GROUP_ROLES" == "No matching entries." ]]; then
        log_message "NOTE: AD Group '$AD_GROUP_EMAIL' not found or has no direct roles assigned in project '$PROJECT_ID'."
    else
        log_message "IAM Roles for AD Group '$AD_GROUP_EMAIL' in Project '$PROJECT_ID':"
        echo "$AD_GROUP_ROLES" | tee -a "$LOG_FILE" # Use tee to print to console and log file
    fi

    # 3. Get Service Accounts with "vertex" in their name and their IAM roles
    log_message "Fetching 'vertex' service accounts and their IAM roles in project '$PROJECT_ID'..."

    # List all service accounts in the project
    SERVICE_ACCOUNTS=$(gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)" 2>/dev/null)

    if [[ -z "$SERVICE_ACCOUNTS" ]]; then
        log_message "NOTE: No service accounts found in project '$PROJECT_ID'."
    else
        VERTEX_SA_FOUND=false
        while IFS= read -r SA_EMAIL; do
            if [[ "$SA_EMAIL" == *"vertex"* ]]; then
                VERTEX_SA_FOUND=true
                log_message "Found Vertex Service Account: $SA_EMAIL"
                SA_ROLES=$(gcloud projects get-iam-policy "$PROJECT_ID" \
                    --flatten="bindings[].members" \
                    --format="table(bindings.role,bindings.members)" \
                    --filter="bindings.members:'serviceAccount:$SA_EMAIL'" 2>/dev/null)

                if [[ -z "$SA_ROLES" || "$SA_ROLES" == "No matching entries." ]]; then
                    log_message "NOTE: Service Account '$SA_EMAIL' has no direct roles assigned in project '$PROJECT_ID'."
                else
                    log_message "IAM Roles for Vertex Service Account '$SA_EMAIL' in Project '$PROJECT_ID':"
                    echo "$SA_ROLES" | tee -a "$LOG_FILE"
                fi
            fi
        done <<< "$SERVICE_ACCOUNTS"

        if ! $VERTEX_SA_FOUND; then
            log_message "NOTE: No service accounts with 'vertex' in their name found in project '$PROJECT_ID'."
        fi
    fi

    log_message "----------------------------------------------------"

done < "$MAPPING_FILE"

log_message "IAM Roles Report Generation Completed."
log_message "Output saved to '$LOG_FILE' (if enabled) and displayed on console."
