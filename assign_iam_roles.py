import argparse
import json
import sys
import os
from google.cloud import resourcemanager_v3

# Ensure the required Google Cloud library is installed.
try:
    from google.cloud import resourcemanager_v3
except ImportError:
    print("Error: The 'google-cloud-resourcemanager' library is not installed.", file=sys.stderr)
    print("Please install it: pip install google-cloud-resourcemanager", file=sys.stderr)
    sys.exit(1)

def get_bundled_roles(bundle_name):
    """
    Resolves a bundled role name to a list of individual IAM roles.
    Includes only the specified job function role options.
    """
    bundled_roles_map = {
        "GenAIUser": [
            "roles/artifactregistry.admin",
            "roles/aiplatform.user",
            "roles/notebooks.admin",
            "roles/storage.admin",
            "roles/bigquery.dataEditor",
            "roles/bigquery.jobUser",
            "roles/dlp.admin"
        ],
        "GenAIViewer": [
            "roles/aiplatform.viewer",
            "roles/bigquery.dataViewer",
            "roles/storage.objectViewer",
            "roles/notebooks.viewer",
            "roles/dlp.jobsReader"
        ],
        "GenAIFeatureStoreUser": [
            "roles/aiplatform.featurestoreUser"
        ],
        "GenAIFeatureStoreViewer": [
            "roles/aiplatform.featurestoreDataViewer",
            "roles/aiplatform.featurestoreResourceViewer"
        ],
        "GenAppBuilderUser": [
            "roles/discoveryengine.editor"
        ]
    }
    return bundled_roles_map.get(bundle_name, [])

def get_member_string(member_type, email):
    """
    Formats the member string for IAM policies.
    """
    if member_type == "serviceAccount":
        return f"serviceAccount:{email}"
    elif member_type == "ad_group": # Mapping 'ad_group' to 'group' for GCP IAM
        return f"group:{email}"
    elif member_type == "user": # Just in case it's a user email
        return f"user:{email}"
    else:
        raise ValueError(f"Unknown member type: {member_type}")

def add_or_update_binding(policy, role, member_string):
    """
    Adds or updates a role binding in the IAM policy.
    Ensures no conditions are set.
    """
    found_binding = False
    for binding in policy.get('bindings', []):
        if binding.get('role') == role:
            # Check for existing member
            if member_string not in binding.get('members', []):
                binding['members'].append(member_string)
                # Ensure members are unique and sorted for consistency (optional but good practice)
                binding['members'] = sorted(list(set(binding['members'])))
                print(f"  Added member '{member_string}' to existing role '{role}'.")
            else:
                print(f"  Member '{member_string}' already exists in role '{role}'. Skipping.")
            # Ensure no condition exists for this binding
            if 'condition' in binding:
                del binding['condition']
                print(f"  Removed condition from role '{role}' binding.")
            found_binding = True
            break

    if not found_binding:
        # Create a new binding if it doesn't exist
        new_binding = {
            "role": role,
            "members": [member_string]
            # No 'condition' key, as per requirement
        }
        if 'bindings' not in policy or policy['bindings'] is None:
            policy['bindings'] = []
        policy['bindings'].append(new_binding)
        print(f"  Added new binding for role '{role}' with member '{member_string}'.")

    return policy

def main():
    parser = argparse.ArgumentParser(description="Automate assigning IAM roles to a Google Service Account or AD Group.")
    parser.add_argument("--mode", required=True, choices=["dry-run", "apply"], help="Operation mode.")
    parser.add_argument("--project-id", required=True, help="The GCP Project ID.")
    parser.add_argument("--target-type", required=True, choices=["service_account", "ad_group"], help="Type of principal.")
    parser.add_argument("--service-account-email", help="Email of the GCP Service Account.")
    parser.add_argument("--ad-group-email", help="Email of the Active Directory Group.")
    parser.add_argument("--roles", default="", help="Comma-separated individual IAM roles.")
    parser.add_argument("--bundled-roles", default="", help="Name of a predefined bundled role.")

    args = parser.parse_args()

    project_id = args.project_id
    mode = args.mode

    if args.target_type == "service_account":
        target_email = args.service_account_email
        if not target_email:
            print("Error: --service-account-email is required for target_type 'service_account'.", file=sys.stderr)
            sys.exit(1)
        member_type = "serviceAccount"
        print(f"Processing roles for Service Account: {target_email}")
    else: # ad_group
        target_email = args.ad_group_email
        if not target_email:
            print("Error: --ad-group-email is required for target_type 'ad_group'.", file=sys.stderr)
            sys.exit(1)
        member_type = "ad_group" # This will be mapped to 'group' in get_member_string
        print(f"Processing roles for AD Group: {target_email}")

    all_roles_to_assign = set() # Use a set to automatically handle duplicates

    # Add individual roles
    if args.roles:
        all_roles_to_assign.update([r.strip() for r in args.roles.split(',') if r.strip()])

    # Add bundled roles
    if args.bundled_roles:
        resolved_roles = get_bundled_roles(args.bundled_roles)
        if not resolved_roles:
            print(f"Error: Unknown bundled role name: '{args.bundled_roles}'. Exiting.", file=sys.stderr)
            sys.exit(1)
        all_roles_to_assign.update(resolved_roles)

    if not all_roles_to_assign:
        print("No roles specified to assign. Exiting.", file=sys.stderr)
        sys.exit(0)

    # --- Fetch current IAM policy ---
    client = resourcemanager_v3.ProjectsClient()
    project_name = client.project_path(project_id)

    print(f"Fetching current IAM policy for project '{project_id}'...")
    try:
        current_policy = client.get_iam_policy(resource=project_name)
        # Convert policy to a dictionary for easier manipulation
        current_policy_dict = type(current_policy).to_dict(current_policy)
        print("Current IAM policy fetched successfully.")
    except Exception as e:
        print(f"Error fetching IAM policy: {e}", file=sys.stderr)
        print("Ensure the service account running this has 'roles/resourcemanager.projectIamViewer' on the project.", file=sys.stderr)
        sys.exit(1)

    # --- Modify policy ---
    modified_policy_dict = current_policy_dict.copy()
    member_string = get_member_string(member_type, target_email)

    print(f"Applying desired roles to policy for '{member_string}'...")
    for role in sorted(list(all_roles_to_assign)): # Process roles in a consistent order
        modified_policy_dict = add_or_update_binding(modified_policy_dict, role, member_string)

    # Convert back to Policy object for setting
    modified_policy = resourcemanager_v3.Policy(
        version=modified_policy_dict.get('version', 1), # Default to version 1 if not present
        bindings=[
            resourcemanager_v3.Binding(
                role=b['role'],
                members=b['members'],
                # Condition is explicitly omitted as per requirement, if present in dict, it's ignored
            ) for b in modified_policy_dict.get('bindings', [])
        ],
        etag=modified_policy_dict.get('etag', b"") # Use etag from fetched policy, or empty bytes
    )


    # --- Dry Run vs. Apply ---
    if mode == "dry-run":
        print("\n--- Dry Run Output (Proposed IAM Policy) ---")
        # Ensure the etag is correctly represented for display
        display_policy = modified_policy_dict.copy()
        if 'etag' in display_policy:
            # etag comes as bytes from the API, convert to string for JSON display
            display_policy['etag'] = display_policy['etag'].decode('utf-8')
        print(json.dumps(display_policy, indent=2))
        print("--- End Dry Run Output ---")
        print("Validation successful: Proposed changes are displayed above. No changes have been applied to GCP.")
    elif mode == "apply":
        print("\nApplying modified IAM policy...")
        try:
            # The client's set_iam_policy method takes a Policy object directly
            response_policy = client.set_iam_policy(
                resource=project_name,
                policy=modified_policy
            )
            response_policy_dict = type(response_policy).to_dict(response_policy)
            print("IAM policy applied successfully.")
            print("\nNew policy after application:")
            print(json.dumps(response_policy_dict, indent=2))
        except Exception as e:
            print(f"Error applying IAM policy: {e}", file=sys.stderr)
            print("Ensure the service account running this has 'roles/resourcemanager.projectIamAdmin' or 'roles/iam.securityAdmin' on the project.", file=sys.stderr)
            sys.exit(1)

    sys.exit(0)

if __name__ == "__main__":
    main()
