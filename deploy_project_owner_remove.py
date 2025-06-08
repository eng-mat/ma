import argparse
import json
import subprocess
import sys
import os

def run_command(command_args, expect_json=True):
    """
    Runs a command, handles errors, and returns the output.
    If expect_json is True, it parses the stdout as JSON.
    """
    try:
        # Add --format=json if we expect a JSON response and it's a gcloud command
        if expect_json and command_args[0] == 'gcloud':
            command_args.append("--format=json")

        process = subprocess.run(
            command_args,
            capture_output=True,
            text=True,
            check=False,
        )

        if process.returncode != 0:
            print(f"Error: Command failed: {' '.join(command_args)}", file=sys.stderr)
            print(f"Stderr:\n{process.stderr}", file=sys.stderr)
            sys.exit(process.returncode)

        if expect_json:
            return json.loads(process.stdout)

        return process.stdout.strip()
    except Exception as e:
        print(f"An unexpected error occurred while running command: {e}", file=sys.stderr)
        sys.exit(1)


def find_project_id_from_state():
    """
    Finds the GCP Project ID by inspecting the Terraform state.
    This avoids the need for a terraform output block.
    """
    print("[1/4] Reading Terraform state to find the project ID...")
    
    # Use 'terraform show' which provides a stable JSON structure for automation
    state_data = run_command(["terraform", "show", "-json"])
    
    # Iterate through all resources in the state file
    for resource in state_data.get("values", {}).get("root_module", {}).get("resources", []):
        # Find the resource of type 'google_project'
        if resource.get("type") == "google_project":
            project_id = resource.get("values", {}).get("project_id")
            if project_id:
                print(f"   Success: Found Project ID '{project_id}' in the state file.")
                return project_id

    # If we finish the loop and haven't found it, exit with an error
    print("Error: Could not find a 'google_project' resource in the terraform state.", file=sys.stderr)
    print("Please ensure 'terraform apply' has created a GCP project in this workspace.", file=sys.stderr)
    sys.exit(1)


def main():
    """
    Main function to find a project ID from state and then safely remove
    the 'owner' role from a service account on that project.
    """
    parser = argparse.ArgumentParser(
        description="Finds project ID from state and safely removes 'roles/owner'."
    )
    parser.add_argument("--service-account-email", required=True, help="Email of the GCP Service Account.")
    args = parser.parse_args()

    # Step 1: Automatically find the Project ID from the state file
    project_id = find_project_id_from_state()

    member_to_remove = f"serviceAccount:{args.service_account_email}"
    role_to_remove = "roles/owner"

    print(f"\n[2/4] Fetching current IAM policy for project '{project_id}'...")
    policy = run_command(["gcloud", "projects", "get-iam-policy", project_id])
    
    original_etag = policy.get("etag")
    if not original_etag:
        print("Error: Could not retrieve etag from policy. Cannot proceed safely.", file=sys.stderr)
        sys.exit(1)

    print("[3/4] Checking policy for member and role...")
    policy_modified = False
    owner_binding = next((b for b in policy.get("bindings", []) if b.get("role") == role_to_remove), None)

    if owner_binding and member_to_remove in owner_binding.get("members", []):
        print(f"   Success: Found '{member_to_remove}' in the '{role_to_remove}' binding.")
        owner_binding["members"].remove(member_to_remove)
        policy_modified = True
        
        if not owner_binding["members"]:
            policy["bindings"].remove(owner_binding)
            print("   Action: The 'roles/owner' binding is now empty and will be removed.")
        else:
            print(f"   Action: Member '{member_to_remove}' will be removed from the binding.")
    else:
        print(f"   Success: Member '{member_to_remove}' does not have the '{role_to_remove}' role. No changes needed.")

    if policy_modified:
        print("\n[4/4] Applying modified IAM policy...")
        temp_policy_file = "updated_policy.json"
        with open(temp_policy_file, "w") as f:
            json.dump(policy, f)
            
        try:
            run_command(
                ["gcloud", "projects", "set-iam-policy", project_id, temp_policy_file],
                expect_json=False
            )
            print("   Success: IAM policy updated successfully.")
        finally:
            if os.path.exists(temp_policy_file):
                os.remove(temp_policy_file)
    else:
        print("\n[4/4] No changes were necessary. Script finished.")


if __name__ == "__main__":
    main()