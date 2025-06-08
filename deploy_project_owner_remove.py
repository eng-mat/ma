# scripts/remove_owner_role.py

import argparse
import json
import subprocess
import sys
import os

def run_gcloud_command(command_args, expect_json=True):
    """
    Runs a gcloud command, handles errors, and returns the output.
    If expect_json is True, it parses the stdout as JSON.
    """
    try:
        # Add --format=json if we expect a JSON response
        if expect_json:
            command_args.append("--format=json")

        process = subprocess.run(
            ["gcloud"] + command_args,
            capture_output=True,
            text=True,
            check=False, # We will check the returncode manually
        )

        if process.returncode != 0:
            print(f"Error: gcloud command failed: {' '.join(['gcloud'] + command_args)}", file=sys.stderr)
            print(f"gcloud stderr:\n{process.stderr}", file=sys.stderr)
            sys.exit(process.returncode)

        if expect_json:
            if not process.stdout.strip():
                # This can happen if a command has no output, which is not an error
                # for some commands like set-iam-policy. We return an empty dict.
                return {}
            return json.loads(process.stdout)

        return process.stdout.strip()

    except FileNotFoundError:
        print("Error: gcloud CLI not found. Please ensure it's installed and in your PATH.", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Failed to decode JSON from gcloud output: {e}", file=sys.stderr)
        print(f"Raw gcloud stdout that caused error:\n{process.stdout}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    """
    Main function to safely remove the 'owner' role from a service account
    on a specified GCP project using a read-modify-write cycle.
    """
    parser = argparse.ArgumentParser(
        description="Safely removes the 'roles/owner' from a service account on a GCP project."
    )
    parser.add_argument("--project-id", required=True, help="The GCP Project ID.")
    parser.add_argument("--service-account-email", required=True, help="Email of the GCP Service Account to remove as owner.")
    args = parser.parse_args()

    member_to_remove = f"serviceAccount:{args.service_account_email}"
    role_to_remove = "roles/owner"

    print(f"-> Starting removal process for project '{args.project_id}'")
    print(f"   Target Member: {member_to_remove}")
    print(f"   Target Role:   {role_to_remove}")

    # 1. READ: Get the current IAM policy
    print("\n[1/3] Fetching current IAM policy...")
    policy = run_gcloud_command(["projects", "get-iam-policy", args.project_id])
    
    # Store the original etag for safe, concurrent updates
    original_etag = policy.get("etag")
    if not original_etag:
        print("Error: Could not retrieve etag from policy. Cannot proceed safely.", file=sys.stderr)
        sys.exit(1)

    # 2. MODIFY: Check for the binding and remove the member if it exists
    print("[2/3] Checking policy for member and role...")
    policy_modified = False
    
    # Find the specific binding for 'roles/owner'
    owner_binding = next((b for b in policy.get("bindings", []) if b.get("role") == role_to_remove), None)

    if owner_binding and member_to_remove in owner_binding.get("members", []):
        print(f"   Success: Found '{member_to_remove}' in the '{role_to_remove}' binding.")
        
        # Remove the specific member from the binding
        owner_binding["members"].remove(member_to_remove)
        policy_modified = True
        
        # If the members list is now empty, remove the entire binding object
        if not owner_binding["members"]:
            policy["bindings"].remove(owner_binding)
            print("   Action: The 'roles/owner' binding is now empty and will be removed.")
        else:
            print(f"   Action: Member '{member_to_remove}' will be removed from the binding.")
            
    else:
        print(f"   Success: Member '{member_to_remove}' does not have the '{role_to_remove}' role. No changes needed.")

    # 3. WRITE: Apply the new policy only if it was modified
    if policy_modified:
        print("\n[3/3] Applying modified IAM policy...")
        
        # Write the modified policy to a temporary file
        temp_policy_file = "updated_policy.json"
        with open(temp_policy_file, "w") as f:
            json.dump(policy, f)
            
        try:
            # Apply the policy from the file
            run_gcloud_command(
                ["projects", "set-iam-policy", args.project_id, temp_policy_file],
                expect_json=False # set-iam-policy may not return JSON on success
            )
            print("   Success: IAM policy updated successfully.")
        finally:
            # Clean up the temporary file
            if os.path.exists(temp_policy_file):
                os.remove(temp_policy_file)
    else:
        print("\n[3/3] No changes were necessary. Script finished.")

if __name__ == "__main__":
    main()