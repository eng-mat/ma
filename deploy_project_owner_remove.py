import argparse
import json
import subprocess
import sys
import os

def run_command(command_args, expect_json=True):
    """
    Runs a command and handles its output with maximum robustness.
    """
    try:
        process = subprocess.run(
            command_args,
            capture_output=True,
            text=True,
            check=False,
        )

        stdout = process.stdout
        stderr = process.stderr

        if process.returncode != 0:
            print(f"Error: Command failed: {' '.join(command_args)}", file=sys.stderr)
            print(f"--- Stderr ---", file=sys.stderr)
            print(stderr, file=sys.stderr)
            sys.exit(process.returncode)

        if expect_json:
            try:
                # --- FINAL, MOST PRECISE LOGIC ---
                # Find the start of the JSON object.
                json_start_index = stdout.find('{')
                if json_start_index == -1:
                    raise json.JSONDecodeError("No JSON object start character '{' found.", stdout, 0)

                # Find the end of the JSON object by finding the LAST '}'.
                # This handles garbage text appearing *after* the JSON.
                json_end_index = stdout.rfind('}')
                if json_end_index == -1:
                    raise json.JSONDecodeError("No JSON object end character '}' found.", stdout, 0)

                # Slice the string precisely from the first '{' to the last '}' (inclusive).
                json_string = stdout[json_start_index : json_end_index + 1]
                
                # Parse the perfectly sliced, clean string.
                return json.loads(json_string)

            except json.JSONDecodeError as e:
                print("--- PYTHON SCRIPT: FAILED TO PARSE JSON ---", file=sys.stderr)
                print(f"   JSONDecodeError: {e}", file=sys.stderr)
                print("--- The raw text output that failed to parse was: ---", file=sys.stderr)
                print(stdout, file=sys.stderr)
                print("--- End of raw text output ---", file=sys.stderr)
                sys.exit(1)

        return stdout.strip()
    except Exception as e:
        print(f"An unexpected Python error occurred: {e}", file=sys.stderr)
        sys.exit(1)

def find_project_id_from_state():
    """Finds the GCP Project ID by running 'terraform show -json' and parsing the output."""
    print("[1/4] Running 'terraform show -json' to find the project ID...")
    state_data = run_command(["terraform", "show", "-json"])
    
    for resource in state_data.get("values", {}).get("root_module", {}).get("resources", []):
        if resource.get("type") == "google_project":
            project_id = resource.get("values", {}).get("project_id")
            if project_id:
                print(f"   Success: Found Project ID '{project_id}' in the state file.")
                return project_id

    print("Error: Could not find a 'google_project' resource in the Terraform state.", file=sys.stderr)
    sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Finds project ID from state and removes 'owner' role.")
    parser.add_argument("--service-account-email", required=True, help="Email of the GCP Service Account.")
    args = parser.parse_args()

    project_id = find_project_id_from_state()
    member_to_remove = f"serviceAccount:{args.service_account_email}"
    role_to_remove = "roles/owner"

    print(f"\n[2/4] Fetching current IAM policy for project '{project_id}'...")
    policy = run_command(["gcloud", "projects", "get-iam-policy", project_id])
    
    original_etag = policy.get("etag")
    if not original_etag:
        print("Error: Could not retrieve etag from policy.", file=sys.stderr)
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
            run_command(["gcloud", "projects", "set-iam-policy", project_id, temp_policy_file], expect_json=False)
            print("   Success: IAM policy updated successfully.")
        finally:
            if os.path.exists(temp_policy_file):
                os.remove(temp_policy_file)
    else:
        print("\n[4/4] No changes were necessary. Script finished.")

if __name__ == "__main__":
    main()