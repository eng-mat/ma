# Sample file filename.txt
#my-project-1 ad-group-alpha@example.com
#dev-project-2 ad-group-beta@example.com

# chmod +x get_iam_roles.sh
# ./get_iam_roles.sh



#!/bin/bash

# File containing project to AD group mappings (e.g., project-id ad-group@yourdomain.com)
MAPPING_FILE="project_group_mapping.txt"

# Output CSV file for detailed and summary reports
CSV_FILE="iam_roles_report.csv"

# Output file for detailed logging (optional, in addition to CSV)
LOG_FILE="iam_roles_report.log"

# Function to log messages to console and log file
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

log_message "Starting IAM Roles Report Generation (Detailed & Summary)..."
log_message "----------------------------------------------------"

# Check if the mapping file exists
if [[ ! -f "$MAPPING_FILE" ]]; then
    log_message "ERROR: Mapping file '$MAPPING_FILE' not found. Please create it with project ID and AD group mappings."
    exit 1
fi

# --- Stage 1: Generate Detailed Report ---
log_message "Stage 1: Generating Detailed IAM Roles Report..."

# Initialize the CSV file with headers
echo "Project_ID,Member_Type,Member_Email,Role" > "$CSV_FILE"
log_message "Initialized CSV file: '$CSV_FILE' with detailed headers."

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
        echo "\"$PROJECT_ID\",\"N/A\",\"N/A\",\"Project Not Found/Decommissioned\"" >> "$CSV_FILE"
        log_message "----------------------------------------------------"
        continue
    fi

    log_message "Project '$PROJECT_ID' found."

    # 2. Get IAM roles for the AD Group
    log_message "Fetching IAM roles for AD Group '$AD_GROUP_EMAIL' in project '$PROJECT_ID'..."
    AD_GROUP_ROLES_CSV=$(gcloud projects get-iam-policy "$PROJECT_ID" \
        --flatten="bindings[].members" \
        --format="csv(bindings.role,bindings.members)" \
        --filter="bindings.members:'group:$AD_GROUP_EMAIL'" 2>/dev/null | tail -n +2)

    if [[ -z "$AD_GROUP_ROLES_CSV" ]]; then
        log_message "NOTE: AD Group '$AD_GROUP_EMAIL' not found or has no direct roles assigned in project '$PROJECT_ID'."
        echo "\"$PROJECT_ID\",\"AD_Group\",\"$AD_GROUP_EMAIL\",\"No Direct Roles Found\"" >> "$CSV_FILE"
    else
        log_message "Exporting IAM Roles for AD Group '$AD_GROUP_EMAIL' to CSV."
        while IFS=',' read -r role member; do
            clean_member=$(echo "$member" | sed 's/^group://')
            echo "\"$PROJECT_ID\",\"AD_Group\",\"$clean_member\",\"$role\"" >> "$CSV_FILE"
        done <<< "$AD_GROUP_ROLES_CSV"
    fi

    # 3. Get Service Accounts with "vertex" in their name and their IAM roles
    log_message "Fetching 'vertex' service accounts and their IAM roles in project '$PROJECT_ID'..."

    SERVICE_ACCOUNTS=$(gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)" 2>/dev/null)

    if [[ -z "$SERVICE_ACCOUNTS" ]]; then
        log_message "NOTE: No service accounts found in project '$PROJECT_ID'."
        echo "\"$PROJECT_ID\",\"Service_Account\",\"N/A\",\"No Service Accounts Found\"" >> "$CSV_FILE"
    else
        VERTEX_SA_FOUND=false
        while IFS= read -r SA_EMAIL; do
            if [[ "$SA_EMAIL" == *"vertex"* ]]; then
                VERTEX_SA_FOUND=true
                log_message "Found Vertex Service Account: $SA_EMAIL"
                SA_ROLES_CSV=$(gcloud projects get-iam-policy "$PROJECT_ID" \
                    --flatten="bindings[].members" \
                    --format="csv(bindings.role,bindings.members)" \
                    --filter="bindings.members:'serviceAccount:$SA_EMAIL'" 2>/dev/null | tail -n +2)

                if [[ -z "$SA_ROLES_CSV" ]]; then
                    log_message "NOTE: Service Account '$SA_EMAIL' has no direct roles assigned in project '$PROJECT_ID'."
                    echo "\"$PROJECT_ID\",\"Service_Account\",\"$SA_EMAIL\",\"No Direct Roles Found\"" >> "$CSV_FILE"
                else
                    log_message "Exporting IAM Roles for Vertex Service Account '$SA_EMAIL' to CSV."
                    while IFS=',' read -r role member; do
                        clean_member=$(echo "$member" | sed 's/^serviceAccount://')
                        echo "\"$PROJECT_ID\",\"Service_Account\",\"$clean_member\",\"$role\"" >> "$CSV_FILE"
                    done <<< "$SA_ROLES_CSV"
                fi
            fi
        done <<< "$SERVICE_ACCOUNTS"

        if ! $VERTEX_SA_FOUND; then
            log_message "NOTE: No service accounts with 'vertex' in their name found in project '$PROJECT_ID'."
            echo "\"$PROJECT_ID\",\"Service_Account\",\"N/A\",\"No Vertex SA Found\"" >> "$CSV_FILE"
        fi
    fi

    log_message "----------------------------------------------------"

done < "$MAPPING_FILE"

log_message "Stage 1: Detailed IAM Roles Report Generated to '$CSV_FILE'."
log_message "----------------------------------------------------"


# --- Stage 2: Generate Summary Report from the Detailed CSV ---
log_message "Stage 2: Generating Summary Report..."

# Add a separator and new header for the summary section
echo "" >> "$CSV_FILE"
echo "--- Summary Report ---" >> "$CSV_FILE"
echo "Member_Type,Member_Email,Project_Count,Unique_Roles" >> "$CSV_FILE"
log_message "Added summary section headers to '$CSV_FILE'."

declare -A ad_group_roles # Associative array to store unique roles for each AD Group
declare -A ad_group_projects # Associative array to store project count for each AD Group
declare -A vertex_sa_roles # Associative array to store unique roles for each Vertex SA
declare -A vertex_sa_projects # Associative array to store project count for each Vertex SA

# Read the generated detailed CSV, skipping header and empty lines
tail -n +2 "$CSV_FILE" | grep -v '^\s*$' | while IFS=',' read -r project_id member_type member_email role; do
    # Remove leading/trailing quotes and trim whitespace from fields
    project_id=$(echo "$project_id" | sed 's/^"//;s/"$//;s/^[[:space:]]*//;s/[[:space:]]*$//')
    member_type=$(echo "$member_type" | sed 's/^"//;s/"$//;s/^[[:space:]]*//;s/[[:space:]]*$//')
    member_email=$(echo "$member_email" | sed 's/^"//;s/"$//;s/^[[:space:]]*//;s/[[:space:]]*$//')
    role=$(echo "$role" | sed 's/^"//;s/"$//;s/^[[:space:]]*//;s/[[:space:]]*$//')

    # Skip lines that are just notes (e.g., "Project Not Found")
    if [[ "$role" == "Project Not Found/Decommissioned" || "$role" == "No Direct Roles Found" || "$role" == "No Service Accounts Found" || "$role" == "No Vertex SA Found" ]]; then
        continue
    fi

    if [[ "$member_type" == "AD_Group" ]]; then
        # Add role to the unique set for this AD Group
        if [[ -z "${ad_group_roles[$member_email]}" ]]; then
            ad_group_roles[$member_email]="$role"
        else
            # Append if not already present (using regex for distinct check)
            if ! echo "${ad_group_roles[$member_email]}" | grep -q "\<$role\>"; then
                ad_group_roles[$member_email]+=", $role"
            fi
        fi
        # Increment project count for this AD Group
        if [[ -z "${ad_group_projects[$member_email]}" ]]; then
            ad_group_projects[$member_email]="($project_id)"
        else
            if ! echo "${ad_group_projects[$member_email]}" | grep -q "\<$project_id\>"; then
                 ad_group_projects[$member_email]+=", ($project_id)"
            fi
        fi
    elif [[ "$member_type" == "Service_Account" ]]; then
        # Add role to the unique set for this Vertex SA
        if [[ -z "${vertex_sa_roles[$member_email]}" ]]; then
            vertex_sa_roles[$member_email]="$role"
        else
            if ! echo "${vertex_sa_roles[$member_email]}" | grep -q "\<$role\>"; then
                vertex_sa_roles[$member_email]+=", $role"
            fi
        fi
        # Increment project count for this Vertex SA
        if [[ -z "${vertex_sa_projects[$member_email]}" ]]; then
            vertex_sa_projects[$member_email]="($project_id)"
        else
            if ! echo "${vertex_sa_projects[$member_email]}" | grep -q "\<$project_id\>"; then
                vertex_sa_projects[$member_email]+=", ($project_id)"
            fi
        fi
    fi
done

# Output summarized AD Group roles
log_message "Writing summarized AD Group roles to CSV..."
for email in "${!ad_group_roles[@]}"; do
    # Sort roles and remove duplicates (commas are separators for roles)
    sorted_roles=$(echo "${ad_group_roles[$email]}" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
    # Count unique projects
    project_list=$(echo "${ad_group_projects[$email]}" | tr ',' '\n' | sed 's/[()]//g' | tr ' ' '\n' | sort -u | wc -l)
    echo "\"AD_Group\",\"$email\",\"$project_list\",\"$sorted_roles\"" >> "$CSV_FILE"
done

# Output summarized Vertex Service Account roles
log_message "Writing summarized Vertex Service Account roles to CSV..."
for email in "${!vertex_sa_roles[@]}"; do
    # Sort roles and remove duplicates
    sorted_roles=$(echo "${vertex_sa_roles[$email]}" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
    # Count unique projects
    project_list=$(echo "${vertex_sa_projects[$email]}" | tr ',' '\n' | sed 's/[()]//g' | tr ' ' '\n' | sort -u | wc -l)
    echo "\"Service_Account\",\"$email\",\"$project_list\",\"$sorted_roles\"" >> "$CSV_FILE"
done

log_message "Stage 2: Summary Report Appended to '$CSV_FILE'."
log_message "IAM Roles Report Generation Completed."
log_message "Full report (detailed and summary) is in '$CSV_FILE'."
log_message "Detailed logs available in '$LOG_FILE'."
