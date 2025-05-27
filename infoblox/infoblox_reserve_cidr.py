import argparse
import requests
import json
import ipaddress
import os # Import the 'os' module to access environment variables
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s]: %(message)s')
logger = logging.getLogger(__name__)

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

def find_next_available_cidr(session, infoblox_url, network_view, supernet_ip, cidr_block_size):
    """
    Finds the next available CIDR block within the specified supernet and network view.
    This function needs to interact with your Infoblox WAPI to determine the next available network.
    """
    # Infoblox WAPI URL and Parameters for 'next_available_network'
    # Adjust WAPI version (e.g., v2.10, v2.11) to match your Infoblox appliance.
    wapi_url = f"{infoblox_url}/wapi/v2.10/network"

    params = {
        "_return_fields+": "network,network_view,comment,extattrs",
        "network_view": network_view,
        "network": supernet_ip,
        "next_available_network": f"{cidr_block_size}" # This is a common WAPI parameter for finding next available
    }

    logger.info(f"Attempting to find next available /{cidr_block_size} in View: {network_view} | Supernet: {supernet_ip}...")
    try:
        response = session.get(wapi_url, params=params, timeout=30)
        response.raise_for_status() # Raise an exception for HTTP errors (4xx or 5xx)
        data = response.json()

        if data and isinstance(data, list) and len(data) > 0:
            # Assuming the Infoblox API returns the next available network in the first item
            proposed_network = data[0].get('network')
            if proposed_network:
                logger.info(f"SUCCESS: Proposed network found: {proposed_network}")
                return proposed_network
            else:
                logger.error("ERROR: 'network' field not found in Infoblox response for next available network.")
                logger.error(f"Raw Infoblox Response: {json.dumps(data, indent=2)}")
                return None
        else:
            logger.error(f"ERROR: No available network found or invalid response from Infoblox for {supernet_ip} with /{cidr_block_size}.")
            logger.error(f"Raw Infoblox Response: {response.text}")
            return None
    except requests.exceptions.RequestException as e:
        logger.error(f"ERROR: Infoblox API request failed during next_available_network lookup: {e}")
        if response is not None:
            logger.error(f"Infoblox Response: {response.text}")
        return None
    except json.JSONDecodeError:
        logger.error(f"ERROR: Failed to parse JSON response from Infoblox for next_available_network: {response.text}")
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

    logger.info(f"Attempting to reserve CIDR: {proposed_subnet} in network view: {network_view}...")
    try:
        response = session.post(wapi_url, json=payload, timeout=30)
        response.raise_for_status() # Raise an exception for HTTP errors (4xx or 5xx)
        data = response.json()
        logger.info(f"SUCCESS: Successfully reserved CIDR: {proposed_subnet}. Infoblox Ref: {data.get('_ref')}")
        return True
    except requests.exceptions.RequestException as e:
        logger.error(f"ERROR: Infoblox API request failed during CIDR reservation: {e}")
        if response is not None:
            logger.error(f"Infoblox Response: {response.text}")
        return False
    except json.JSONDecodeError:
        logger.error(f"ERROR: Failed to parse JSON response from Infoblox during CIDR reservation: {response.text}")
        return False


def get_supernet_info(session, infoblox_url, supernet_ip, network_view): # Added supernet_ip argument
    """
    Fetches information about the supernet. This function is conceptual.
    To provide accurate "supernet status after reservation", you would need
    to query Infoblox for details on the specified supernet (e.g., utilization,
    free space, existing subnets). For simplicity, it returns the supernet CIDR.
    """
    # supernet_ip is now directly passed from the YAML, so no need for internal mapping here.
    logger.info(f"DEBUG: Simulating supernet info for {supernet_ip}. Real implementation would query Infoblox.")
    # In a real scenario, you would perform WAPI calls here
    # e.g., to get network utilization or list existing subnets within the supernet
    return f"Supernet {supernet_ip} in {network_view}" # Return a simplified string for now

def validate_inputs(network_view, supernet_ip, subnet_name, cidr_block_size): # Added supernet_ip argument
    """Performs basic input validations."""
    if not network_view or not supernet_ip or not subnet_name or not cidr_block_size:
        logger.error("Validation Error: All inputs (network_view, supernet_ip, subnet_name, cidr_block_size) are required.")
        return False
    if not (1 <= cidr_block_size <= 32):
        logger.error("Validation Error: CIDR block size must be between 1 and 32.")
        return False
    try:
        ipaddress.ip_network(supernet_ip, strict=False)
    except ValueError:
        logger.error(f"Validation Error: Invalid Supernet IP format: {supernet_ip}")
        return False
    if not subnet_name.strip():
        logger.error("Validation Error: Subnet name cannot be empty.")
        return False
    return True

def main():
    parser = argparse.ArgumentParser(description="Infoblox CIDR Reservation Workflow Script")
    parser.add_argument("action", choices=["dry-run", "apply"], help="Action to perform: dry-run or apply")
    parser.add_argument("--infoblox-url", required=True, help="Infoblox URL (e.g., https://infoblox.example.com)")
    parser.add_argument("--network-view", required=True, help="Infoblox Network View/Container")
    parser.add_argument("--supernet-ip", required=True, help="Supernet IP from which to reserve") # New argument
    parser.add_argument("--subnet-name", required=True, help="Name for the new subnet (used as comment)")
    parser.add_argument("--cidr-block-size", type=int, required=True, help="CIDR block size (e.g., 26 for /26)")
    parser.add_argument("--site-code", required=False, default="GCP", help="Site Code (default: GCP)")
    parser.add_argument("--proposed-subnet", help="Proposed subnet from dry-run (for apply job)")
    parser.add_argument("--supernet-after-reservation", help="Supernet status after reservation (from dry-run)")

    args = parser.parse_args()

    infoblox_username = os.environ.get("INFOBLOX_USERNAME")
    infoblox_password = os.environ.get("INFOBLOX_PASSWORD")

    if not infoblox_username or not infoblox_password:
        logger.error("Infoblox username or password not found in environment variables.")
        logger.error("Ensure INFOBLOX_USERNAME and INFOBLOX_PASSWORD are set in the GitHub Actions workflow environment.")
        exit(1)

    # Pass supernet_ip to validation
    if not validate_inputs(args.network_view, args.supernet_ip, args.subnet_name, args.cidr_block_size):
        exit(1)

    session = get_infoblox_session(args.infoblox_url, infoblox_username, infoblox_password)
    if not session:
        logger.error("Failed to establish Infoblox session. Exiting.")
        exit(1)

    if args.action == "dry-run":
        logger.info("\n--- Performing Dry Run ---")
        # Pass supernet_ip to find_next_available_cidr
        proposed_subnet = find_next_available_cidr(
            session, args.infoblox_url, args.network_view, args.supernet_ip, args.cidr_block_size
        )

        if proposed_subnet:
            logger.info(f"DRY RUN: Proposed Subnet to Reserve: {proposed_subnet}")
            logger.info(f"DRY RUN: Network View: {args.network_view}")
            logger.info(f"DRY RUN: Supernet IP: {args.supernet_ip}") # Log the selected supernet IP
            logger.info(f"DRY RUN: Subnet Name (Comment): {args.subnet_name}")
            logger.info(f"DRY RUN: CIDR Block Size: /{args.cidr_block_size}")
            logger.info(f"DRY RUN: Site Code: {args.site_code}")

            # Pass supernet_ip to get_supernet_info
            supernet_after_reservation = get_supernet_info(
                session, args.infoblox_url, args.supernet_ip, args.network_view
            )
            logger.info(f"DRY RUN: Supernet Status (after hypothetical reservation): {supernet_after_reservation}")

            print(f"::set-output name=proposed_subnet::{proposed_subnet}")
            print(f"::set-output name=supernet_after_reservation::{supernet_after_reservation}")
            logger.info("\nDry run completed successfully. Review the proposed changes before proceeding to apply.")
        else:
            logger.error("DRY RUN FAILED: Could not determine a proposed subnet. Check Infoblox connectivity and available space.")
            exit(1)

    elif args.action == "apply":
        logger.info("\n--- Performing Apply ---")
        if not args.proposed_subnet or not args.supernet_after_reservation:
            logger.error("Apply FAILED: Missing proposed_subnet or supernet_after_reservation from dry run. This indicates a problem with job chaining.")
            exit(1)

        logger.info(f"APPLY: Reserving proposed subnet: {args.proposed_subnet}")
        logger.info(f"APPLY: Network View: {args.network_view}")
        logger.info(f"APPLY: Supernet IP: {args.supernet_ip}") # Log the selected supernet IP
        logger.info(f"APPLY: Subnet Name (Comment): {args.subnet_name}")
        logger.info(f"APPLY: CIDR Block Size: /{args.cidr_block_size}")
        logger.info(f"APPLY: Site Code: {args.site_code}")

        success = reserve_cidr(
            session, args.infoblox_url, args.proposed_subnet, args.network_view, args.subnet_name, args.site_code
        )

        if success:
            logger.info(f"APPLY: Successfully reserved CIDR: {args.proposed_subnet}")
            logger.info(f"APPLY: Supernet status after reservation: {args.supernet_after_reservation}")
            logger.info("\nApply completed successfully. Verify the changes in Infoblox.")
        else:
            logger.error(f"APPLY FAILED: Could not reserve CIDR: {args.proposed_subnet}. Check Infoblox logs for details.")
            exit(1)

if __name__ == "__main__":
    main()
