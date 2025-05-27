import argparse
import requests
import json
import ipaddress
import os # Import the 'os' module to access environment variables

def get_infoblox_session(infoblox_url, username, password):
    """Establishes a session with Infoblox and handles authentication."""
    session = requests.Session()
    session.auth = (username, password)
    # IMPORTANT: In a production environment, you should properly verify SSL certificates.
    # Replace 'session.verify = False' with the path to your CA bundle if needed, e.g.:
    # session.verify = '/path/to/your/ca_bundle.crt'
    # Or ensure Infoblox's certificate is trusted by the system running the GitHub Action.
    session.verify = False # Set to True or a path in production!
    return session

def find_next_available_cidr(session, infoblox_url, network_view, cidr_block_size):
    """
    Finds the next available CIDR block within the specified supernet and network view.
    This function needs to interact with your Infoblox WAPI to determine the next available network.
    """
    # --- HARDCODED SUPERNET MAPPING ---
    # This dictionary maps network views to their corresponding supernet CIDR blocks.
    # Adjust these values to match your Infoblox configuration.
    supernet_mapping = {
        "Production_View": "10.0.0.0/8",
        "Development_View": "172.16.0.0/16",
        "DMZ_View": "192.168.0.0/24",
        "NonRoutable_View": "10.200.0.0/16", # Example of another mapping
        "gcp-hcb-shared-hub": "10.10.0.0/17" # Add your specific view/supernet from the error
    }
    supernet_ip = supernet_mapping.get(network_view)

    if not supernet_ip:
        print(f"ERROR: No supernet defined in the script for network view: '{network_view}'. Please check 'supernet_mapping'.")
        return None

    # Infoblox WAPI URL and Parameters for 'next_available_network'
    # Adjust WAPI version (e.g., v2.10, v2.11) to match your Infoblox appliance.
    wapi_url = f"{infoblox_url}/wapi/v2.10/network"

    params = {
        "_return_fields+": "network,network_view,comment,extattrs",
        "network_view": network_view,
        "network": supernet_ip,
        "next_available_network": f"{cidr_block_size}" # This is a common WAPI parameter for finding next available
    }

    print(f"Attempting to find next available /{cidr_block_size} in {network_view} ({supernet_ip})...")
    try:
        response = session.get(wapi_url, params=params, timeout=30)
        response.raise_for_status() # Raise an exception for HTTP errors (4xx or 5xx)
        data = response.json()

        if data and isinstance(data, list) and len(data) > 0:
            # Assuming the Infoblox API returns the next available network in the first item
            proposed_network = data[0].get('network')
            if proposed_network:
                print(f"SUCCESS: Proposed network found: {proposed_network}")
                return proposed_network
            else:
                print("ERROR: 'network' field not found in Infoblox response for next available network.")
                print(f"Raw Infoblox Response: {json.dumps(data, indent=2)}")
                return None
        else:
            print(f"ERROR: No available network found or invalid response from Infoblox for {supernet_ip} with /{cidr_block_size}.")
            print(f"Raw Infoblox Response: {response.text}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"ERROR: Infoblox API request failed during next_available_network lookup: {e}")
        if response is not None:
            print(f"Infoblox Response: {response.text}")
        return None
    except json.JSONDecodeError:
        print(f"ERROR: Failed to parse JSON response from Infoblox for next_available_network: {response.text}")
        return None

def reserve_cidr(session, infoblox_url, proposed_subnet, network_view, subnet_name, site_code):
    """
    Performs the actual CIDR reservation (network creation) in Infoblox.
    """
    # Infoblox WAPI URL for creating a network object
    wapi_url = f"{infoblox_url}/wapi/v2.10/network" # Adjust WAPI version

    payload = {
        "network": proposed_subnet,
        "network_view": network_view,
        "comment": subnet_name, # Subnet name as comment
        "extattrs": {
            "Site Code": {"value": site_code} # Custom extensible attribute for Site Code
        }
        # Add other required fields for network creation as per your Infoblox setup,
        # e.g., 'options', 'members', 'network_container', etc.
    }

    print(f"Attempting to reserve CIDR: {proposed_subnet} in network view: {network_view}...")
    try:
        response = session.post(wapi_url, json=payload, timeout=30)
        response.raise_for_status() # Raise an exception for HTTP errors (4xx or 5xx)
        data = response.json()
        print(f"SUCCESS: Successfully reserved CIDR: {proposed_subnet}. Infoblox Ref: {data.get('_ref')}")
        return True
    except requests.exceptions.RequestException as e:
        print(f"ERROR: Infoblox API request failed during CIDR reservation: {e}")
        if response is not None:
            print(f"Infoblox Response: {response.text}")
        return False
    except json.JSONDecodeError:
        print(f"ERROR: Failed to parse JSON response from Infoblox during CIDR reservation: {response.text}")
        return False


def get_supernet_info(session, infoblox_url, network_view):
    """
    Fetches information about the supernet. This function is conceptual.
    To provide accurate "supernet status after reservation", you would need
    to query Infoblox for details on the specified supernet (e.g., utilization,
    free space, existing subnets). For simplicity, it returns the supernet CIDR.
    """
    # IMPORTANT: Hardcoded mapping of network view to supernet IP
    supernet_mapping = {
        "Production_View": "10.0.0.0/8",
        "Development_View": "172.16.0.0/16",
        "DMZ_View": "192.168.0.0/24",
        "NonRoutable_View": "10.200.0.0/16",
        "gcp-hcb-shared-hub": "10.10.0.0/17" # Add your specific view/supernet from the error
    }
    supernet_ip = supernet_mapping.get(network_view)

    if not supernet_ip:
        print(f"ERROR: No supernet defined in the script for network view: '{network_view}' to get info.")
        return "Unknown"

    print(f"DEBUG: Simulating supernet info for {supernet_ip}. Real implementation would query Infoblox.")
    # In a real scenario, you would perform WAPI calls here
    # e.g., to get network utilization or list existing subnets within the supernet
    return f"Supernet {supernet_ip} in {network_view}" # Return a simplified string for now

def validate_inputs(network_view, subnet_name, cidr_block_size):
    """Performs basic input validations."""
    if not network_view or not subnet_name or not cidr_block_size:
        print("Validation Error: All inputs (network_view, subnet_name, cidr_block_size) are required.")
        return False
    if not (1 <= cidr_block_size <= 32):
        print("Validation Error: CIDR block size must be between 1 and 32.")
        return False
    if not subnet_name.strip():
        print("Validation Error: Subnet name cannot be empty.")
        return False
    # Additional validation for network_view against the hardcoded mapping if needed
    supernet_mapping = {
        "Production_View": "10.0.0.0/8",
        "Development_View": "172.16.0.0/16",
        "DMZ_View": "192.168.0.0/24",
        "NonRoutable_View": "10.200.0.0/16",
        "gcp-hcb-shared-hub": "10.10.0.0/17" # Add your specific view/supernet from the error
    }
    if network_view not in supernet_mapping:
        print(f"Validation Error: Selected network view '{network_view}' is not defined in the script's supernet mapping.")
        return False
    return True

def main():
    parser = argparse.ArgumentParser(description="Infoblox CIDR Reservation Workflow Script")
    parser.add_argument("action", choices=["dry-run", "apply"], help="Action to perform: dry-run or apply")
    # REMOVED: parser.add_argument("--infoblox-url", required=True, help="Infoblox URL (e.g., https://infoblox.example.com)")
    # Username and password are now read from environment variables, not command-line arguments
    parser.add_argument("--network-view", required=True, help="Infoblox Network View/Container")
    parser.add_argument("--subnet-name", required=True, help="Name for the new subnet (used as comment)")
    parser.add_argument("--cidr-block-size", type=int, required=True, help="CIDR block size (e.g., 26 for /26)")
    parser.add_argument("--site-code", required=False, default="GCP", help="Site Code (default: GCP)") # Made not required as it has default
    # Arguments specifically for apply job, passed from dry_run outputs
    parser.add_argument("--proposed-subnet", help="Proposed subnet from dry-run (for apply job)")
    parser.add_argument("--supernet-after-reservation", help="Supernet status after reservation (from dry-run)")

    args = parser.parse_args()

    # Retrieve Infoblox username, password AND URL from environment variables
    infoblox_username = os.environ.get("INFOBLOX_USERNAME")
    infoblox_password = os.environ.get("INFOBLOX_PASSWORD")
    infoblox_url = os.environ.get("INFOBLOX_URL") # <-- NEW: Get URL from environment

    if not infoblox_username or not infoblox_password or not infoblox_url: # <-- NEW: Check URL
        print("ERROR: Missing one or more required environment variables (INFOBLOX_USERNAME, INFOBLOX_PASSWORD, INFOBLOX_URL).")
        print("Ensure these are set in the GitHub Actions workflow environment and retrieved from Secret Manager.")
        exit(1)

    if not validate_inputs(args.network_view, args.subnet_name, args.cidr_block_size):
        exit(1)

    # Establish Infoblox session using credentials from environment variables
    session = get_infoblox_session(infoblox_url, infoblox_username, infoblox_password) # <-- Pass the retrieved URL
    if not session:
        print("Failed to establish Infoblox session. Exiting.")
        exit(1)

    if args.action == "dry-run":
        print("\n--- Performing Dry Run ---")
        proposed_subnet = find_next_available_cidr(
            session, infoblox_url, args.network_view, args.cidr_block_size # <-- Pass the retrieved URL
        )

        if proposed_subnet:
            print(f"DRY RUN: Proposed Subnet to Reserve: {proposed_subnet}")
            print(f"DRY RUN: Network View: {args.network_view}")
            print(f"DRY RUN: Subnet Name (Comment): {args.subnet_name}")
            print(f"DRY RUN: CIDR Block Size: /{args.cidr_block_size}")
            print(f"DRY RUN: Site Code: {args.site_code}")

            # Simulate the supernet status after reservation.
            supernet_after_reservation = get_supernet_info(
                session, infoblox_url, args.network_view # <-- Pass the retrieved URL
            )
            print(f"DRY RUN: Supernet Status (after hypothetical reservation): {supernet_after_reservation}")

            # Output for GitHub Actions - these will be consumed by the 'apply' job
            print(f"::set-output name=proposed_subnet::{proposed_subnet}")
            print(f"::set-output name=supernet_after_reservation::{supernet_after_reservation}")
            print("\nDry run completed successfully. Review the proposed changes before proceeding to apply.")
        else:
            print("DRY RUN FAILED: Could not determine a proposed subnet. Check Infoblox connectivity and available space.")
            exit(1)

    elif args.action == "apply":
        print("\n--- Performing Apply ---")
        if not args.proposed_subnet or not args.supernet_after_reservation:
            print("Apply FAILED: Missing proposed_subnet or supernet_after_reservation from dry run. This indicates a problem with job chaining.")
            exit(1)

        print(f"APPLY: Reserving proposed subnet: {args.proposed_subnet}")
        print(f"APPLY: Network View: {args.network_view}")
        print(f"APPLY: Subnet Name (Comment): {args.subnet_name}")
        print(f"APPLY: CIDR Block Size: /{args.cidr_block_size}")
        print(f"APPLY: Site Code: {args.site_code}")

        success = reserve_cidr(
            session, infoblox_url, args.proposed_subnet, args.network_view, args.subnet_name, args.site_code # <-- Pass the retrieved URL
        )

        if success:
            print(f"APPLY: Successfully reserved CIDR: {args.proposed_subnet}")
            print(f"APPLY: Supernet status after reservation: {args.supernet_after_reservation}")
            print("\nApply completed successfully. Verify the changes in Infoblox.")
        else:
            print(f"APPLY FAILED: Could not reserve CIDR: {args.proposed_subnet}. Check Infoblox logs for details.")
            exit(1)

if __name__ == "__main__":
    main()
