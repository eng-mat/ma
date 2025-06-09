# scripts/remove_owner_role.py

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
        if expect_json and not process.stdout.strip():
             return {}
        return json.loads(process.stdout) if expect_json else process.stdout.strip()
    except Exception as e:
        print(f"An unexpected Python error occurred: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Safely removes the 'owner' role from a service account on a GCP project.")
    parser.add_argument("--project-id", required=True, help="The GCP Project ID.")
    parser.add_argument("--service-account-email", required=True, help="Email of the GCP Service Account.")
    args = parser.parse_args()

    project_id = args.project_id.strip() # Add strip() for extra safety
    member_to_remove = f"serviceAccount:{args.service_account_email}"
    role_to_remove = "roles/owner"

    print(f"-> Starting secure IAM operations for project: '{project_id}'")
    
    print(f"[1/3] Fetching current IAM policy...")
    policy = run_gcloud_command(["projects", "get-iam-policy", project_id])
    
    original_etag = policy.get("etag")
    if not original_etag:
        print("Error: Could not retrieve etag from policy. Cannot proceed safely.", file=sys.stderr)
        sys.exit(1)

    print("[2/3] Checking policy for owner role...")
    policy_modified = False
    owner_binding = next((b for b in policy.get("bindings", []) if b.get("role") == role_to_remove), None)

    if owner_binding and member_to_remove in owner_binding.get("members", []):
        print(f"   Found '{member_to_remove}' in the '{role_to_remove}' binding. Removing it now.")
        owner_binding["members"].remove(member_to_remove)
        policy_modified = True
        if not owner_binding["members"]:
            policy["bindings"].remove(owner_binding)
            print("   Binding is now empty and will be removed from the policy.")
    else:
        print(f"   Member '{member_to_remove}' does not have the '{role_to_remove}' role. No changes needed.")

    if policy_modified:
        print("\n[3/3] Applying modified IAM policy...")
        temp_policy_file = "policy_to_apply.json"
        with open(temp_policy_file, "w") as f:
            json.dump(policy, f)
        try:
            run_gcloud_command(["projects", "set-iam-policy", project_id, temp_policy_file], expect_json=False)
            print("✅ Success: IAM policy updated and owner role removed.")
        finally:
            if os.path.exists(temp_policy_file):
                os.remove(temp_policy_file)
    else:
        print("\n✅ No IAM changes were necessary. Workflow complete.")

if __name__ == "__main__":
    main()