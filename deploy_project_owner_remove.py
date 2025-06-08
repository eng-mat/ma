import argparse
import json
import subprocess
import sys
import os

def run_gcloud_command(command_args, expect_json=True):
    """Runs a gcloud command and returns the output."""
    try:
        if expect_json:
            command_args.append("--format=json")
        
        process = subprocess.run(
            ["gcloud"] + command_args,
            capture_output=True, text=True, check=False
        )

        if process.returncode != 0:
            print(f"Error: gcloud command failed: {' '.join(['gcloud'] + command_args)}", file=sys.stderr)
            print(f"Stderr:\n{process.stderr}", file=sys.stderr)
            sys.exit(process.returncode)

        return json.loads(process.stdout) if expect_json else process.stdout.strip()
    except Exception as e:
        print(f"An unexpected Python error occurred: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Safely removes the 'owner' role from a service account.")
    parser.add_argument("--project-id", required=True, help="The GCP Project ID.")
    parser.add_argument("--service-account-email", required=True, help="Email of the GCP Service Account.")
    args = parser.parse_args()

    project_id = args.project_id
    member_to_remove = f"serviceAccount:{args.service_account_email}"
    role_to_remove = "roles/owner"

    print(f"-> Starting removal process for project '{project_id}'")
    
    print(f"\n[1/3] Fetching current IAM policy for project '{project_id}'...")
    policy = run_gcloud_command(["projects", "get-iam-policy", project_id])
    
    original_etag = policy.get("etag")
    if not original_etag:
        print("Error: Could not retrieve etag from policy.", file=sys.stderr)
        sys.exit(1)

    print("[2/3] Checking policy for member and role...")
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
        print("\n[3/3] Applying modified IAM policy...")
        temp_policy_file = "updated_policy.json"
        with open(temp_policy_file, "w") as f:
            json.dump(policy, f)
        try:
            run_gcloud_command(["projects", "set-iam-policy", project_id, temp_policy_file], expect_json=False)
            print("   Success: IAM policy updated successfully.")
        finally:
            if os.path.exists(temp_policy_file):
                os.remove(temp_policy_file)
    else:
        print("\n[3/3] No changes were necessary. Script finished.")

if __name__ == "__main__":
    main()


# # outputs.tf

# output "project_id" {
#   description = "The constructed ID of the GCP project."
  
#   # This joins the variables together with hyphens to match your project ID format.
#   value       = "${var.project_ab}-${var.project_bbd}-${var.project_bkk}"
# }