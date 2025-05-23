# Sample file filename.txt
#my-project-1 ad-group-alpha@example.com
#dev-project-2 ad-group-beta@example.com

# chmod +x get_iam_roles.sh
# ./get_iam_roles.sh



#!/bin/bash

# File containing project to AD group mappings (e.g., project-id ad-group@yourdomain.com)
MAPPING_FILE="project_group_mapping.txt"

# Output Markdown file for detailed and summary reports
MARKDOWN_FILE="iam_roles_report.md"

# Output file for detailed logging (optional)
LOG_FILE="iam_roles_report.log"

# Function to log messages to console and log file
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

log_message "Starting IAM Roles Report Generation (Detailed & Summary in Markdown)..."
log_message "----------------------------------------------------"

# Check if the mapping file exists
if [[ ! -f "$MAPPING_FILE" ]]; then
    log_message "ERROR: Mapping file '$MAPPING_FILE' not found. Please create it with project ID and AD group mappings."
    exit 1
fi

# --- Stage 1: Generate Detailed Report in Markdown Table and Collect Data for Summary ---
log_message "Stage 1: Generating Detailed IAM Roles Report in Markdown format and collecting data for summary..."

# Initialize the Markdown file with a title and detailed table header
echo "# IAM Roles Report" > "$MARKDOWN_FILE"
echo "" >> "$MARKDOWN_FILE"
echo "## Detailed Report" >> "$MARKDOWN_FILE"
echo "" >> "$MARKDOWN_FILE"
echo "| Project ID | Member Type | Member Email | Role |" >> "$MARKDOWN_FILE"
echo "| :--------- | :---------- | :----------- | :--- |" >> "$MARKDOWN_FILE" # Markdown table separator
log_message "Initialized Markdown file: '$MARKDOWN_FILE' with detailed headers."

# Associative arrays to collect data for the summary report
# Key: Member_Email, Value: space-separated list of unique roles
declare -A ad_group_unique_roles
# Key: Member_Email, Value: space-separated list of unique project IDs
declare -A ad_group_unique_projects

# Key: Member_Email, Value: space-separated list of unique roles
declare -A vertex_sa_unique_roles
# Key: Member_Email, Value: space-separated list of unique project IDs
declare -A vertex_sa_unique_projects

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
        echo "| $PROJECT_ID | N/A | N/A | Project Not Found/Decommissioned |" >> "$MARKDOWN_FILE"
        log_message "----------------------------------------------------"
        continue
    fi

    log_message "Project '$PROJECT_ID' found."

    # 2. Get IAM roles for the AD Group
    log_message "Fetching IAM roles for AD Group '$AD_GROUP_EMAIL' in project '$PROJECT_ID'..."
    AD_GROUP_ROLES_RAW=$(gcloud projects get-iam-policy "$PROJECT_ID" \
        --flatten="bindings[].members" \
        --format="value(bindings.role,bindings.members)" \
        --filter="bindings.members:'group:$AD_GROUP_EMAIL'" 2>/dev/null)

    if [[ -z "$AD_GROUP_ROLES_RAW" ]]; then
        log_message "NOTE: AD Group '$AD_GROUP_EMAIL' not found or has no direct roles assigned in project '$PROJECT_ID'."
        echo "| $PROJECT_ID | AD_Group | $AD_GROUP_EMAIL | No Direct Roles Found |" >> "$MARKDOWN_FILE"
    else
        log_message "Exporting IAM Roles for AD Group '$AD_GROUP_EMAIL' to Markdown."
        while IFS=$'\t' read -r role member; do
            clean_member=$(echo "$member" | sed 's/^group://')
            # Escape pipes within data to not break Markdown table
            escaped_role=$(echo "$role" | sed 's/|/\\|/g')
            escaped_member=$(echo "$clean_member" | sed 's/|/\\|/g')
            echo "| $PROJECT_ID | AD_Group | $escaped_member | $escaped_role |" >> "$MARKDOWN_FILE"

            # Collect data for summary report - AD Group
            ad_group_unique_roles[$clean_member]+=" $role" # Append role
            ad_group_unique_projects[$clean_member]+=" $PROJECT_ID" # Append project
        done <<< "$AD_GROUP_ROLES_RAW"
    fi

    # 3. Get Service Accounts with "vertex" in their name and their IAM roles
    log_message "Fetching 'vertex' service accounts and their IAM roles in project '$PROJECT_ID'..."

    SERVICE_ACCOUNTS=$(gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)" 2>/dev/null)

    if [[ -z "$SERVICE_ACCOUNTS" ]]; then
        log_message "NOTE: No service accounts found in project '$PROJECT_ID'."
        echo "| $PROJECT_ID | Service_Account | N/A | No Service Accounts Found |" >> "$MARKDOWN_FILE"
    else
        VERTEX_SA_FOUND_IN_PROJECT=false
        while IFS= read -r SA_EMAIL; do
            if [[ "$SA_EMAIL" == *"vertex"* ]]; then
                VERTEX_SA_FOUND_IN_PROJECT=true
                log_message "Found Vertex Service Account: $SA_EMAIL"
                SA_ROLES_RAW=$(gcloud projects get-iam-policy "$PROJECT_ID" \
                    --flatten="bindings[].members" \
                    --format="value(bindings.role,bindings.members)" \
                    --filter="bindings.members:'serviceAccount:$SA_EMAIL'" 2>/dev/null)

                if [[ -z "$SA_ROLES_RAW" ]]; then
                    log_message "NOTE: Service Account '$SA_EMAIL' has no direct roles assigned in project '$PROJECT_ID'."
                    echo "| $PROJECT_ID | Service_Account | $SA_EMAIL | No Direct Roles Found |" >> "$MARKDOWN_FILE"
                else
                    log_message "Exporting IAM Roles for Vertex Service Account '$SA_EMAIL' to Markdown."
                    while IFS=$'\t' read -r role member; do
                        clean_member=$(echo "$member" | sed 's/^serviceAccount://')
                        escaped_role=$(echo "$role" | sed 's/|/\\|/g')
                        escaped_member=$(echo "$clean_member" | sed 's/|/\\|/g')
                        echo "| $PROJECT_ID | Service_Account | $escaped_member | $escaped_role |" >> "$MARKDOWN_FILE"

                        # Collect data for summary report - Vertex SA
                        vertex_sa_unique_roles[$clean_member]+=" $role" # Append role
                        vertex_sa_unique_projects[$clean_member]+=" $PROJECT_ID" # Append project
                    done <<< "$SA_ROLES_RAW"
                fi
            fi
        done <<< "$SERVICE_ACCOUNTS"

        if ! $VERTEX_SA_FOUND_IN_PROJECT; then
            log_message "NOTE: No service accounts with 'vertex' in their name found in project '$PROJECT_ID'."
            echo "| $PROJECT_ID | Service_Account | N/A | No Vertex SA Found |" >> "$MARKDOWN_FILE"
        fi
    fi

    log_message "----------------------------------------------------"

done < "$MAPPING_FILE"

log_message "Stage 1: Detailed IAM Roles Report Generated to '$MARKDOWN_FILE'."
log_message "----------------------------------------------------"


# --- Stage 2: Generate Summary Report from Collected Data ---
log_message "Stage 2: Generating Summary Report in Markdown format..."

# Add a separator and new header for the summary section
echo "" >> "$MARKDOWN_FILE"
echo "## Summary Report" >> "$MARKDOWN_FILE"
echo "" >> "$MARKDOWN_FILE"
echo "| Member Type | Member Email | Project Count | Unique Roles |" >> "$MARKDOWN_FILE"
echo "| :---------- | :----------- | :------------ | :----------- |" >> "$MARKDOWN_FILE" # Markdown table separator
log_message "Added summary section headers to '$MARKDOWN_FILE'."

# Output summarized AD Group roles
log_message "Writing summarized AD Group roles to Markdown..."
for email in "${!ad_group_unique_roles[@]}"; do
    # Convert space-separated string of roles to newlines, sort, unique, then join with comma
    unique_roles_str=$(echo "${ad_group_unique_roles[$email]}" | tr ' ' '\n' | sort -u | paste -sd, -)
    # Count unique projects
    unique_project_count=$(echo "${ad_group_unique_projects[$email]}" | tr ' ' '\n' | sort -u | wc -l)

    escaped_roles=$(echo "$unique_roles_str" | sed 's/|/\\|/g') # Escape pipes for Markdown
    echo "| AD_Group | $email | $unique_project_count | $escaped_roles |" >> "$MARKDOWN_FILE"
done

# Output summarized Vertex Service Account roles
log_message "Writing summarized Vertex Service Account roles to Markdown..."
for email in "${!vertex_sa_unique_roles[@]}"; do
    # Convert space-separated string of roles to newlines, sort, unique, then join with comma
    unique_roles_str=$(echo "${vertex_sa_unique_roles[$email]}" | tr ' ' '\n' | sort -u | paste -sd, -)
    # Count unique projects
    unique_project_count=$(echo "${vertex_sa_unique_projects[$email]}" | tr ' ' '\n' | sort -u | wc -l)

    escaped_roles=$(echo "$unique_roles_str" | sed 's/|/\\|/g') # Escape pipes for Markdown
    echo "| Service_Account | $email | $unique_project_count | $escaped_roles |" >> "$MARKDOWN_FILE"
done

log_message "Stage 2: Summary Report Appended to '$MARKDOWN_FILE'."
log_message "IAM Roles Report Generation Completed."
log_message "Full report (detailed and summary) is in '$MARKDOWN_FILE'."
log_message "Detailed logs available in '$LOG_FILE'."
