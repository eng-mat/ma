import argparse
import requests
import json
import ipaddress
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s]: %(message)s')
logger = logging.getLogger(__name__)

def get_infoblox_session(infoblox_url, username, password):
    """Establishes a session with Infoblox and handles authentication."""
    session = requests.Session()
    session.auth = (username, password)
    # InsecureRequestWarning will appear in logs for now.
    # For production, set to True and ensure proper certs, or provide a path to a CA bundle.
    session.verify = False
    return session

def find_next_available_cidr(session, infoblox_url, network_view, supernet_ip, cidr_block_size):
    """
    Finds the next available CIDR block within the specified supernet and network view.
    """
    # Correctly construct the WAPI URL using the full base URL from infoblox_url
    wapi_url = f"{infoblox_url.rstrip('/')}/network"

    logger.info(f"DEBUG SCRIPT: Inside find_next_available_cidr:")
    logger.info(f"DEBUG SCRIPT:   infoblox_url (raw from secret/arg) = '{infoblox_url}'")
    logger.info(f"DEBUG SCRIPT:   constructed wapi_url = '{wapi_url}'")
    logger.info(f"DEBUG SCRIPT:   network_view = '{network_view}'")
    logger.info(f"DEBUG SCRIPT:   supernet_ip (parent network) = '{supernet_ip}'")
    logger.info(f"DEBUG SCRIPT:   cidr_block_size (for new subnet) = '{cidr_block_size}'")

    params = {
        "_return_fields+": "network,network_view",  # Request fields that might be useful
        "network_view": network_view,
        "network": supernet_ip,          # The supernet from which to find the next available
        "cidr": cidr_block_size,         # The size of the network to find
        "num": 1                         # We need one such network
    }
    logger.info(f"DEBUG SCRIPT: Params dictionary being sent to Infoblox for next available: {json.dumps(params, indent=2)}")

    logger.info(f"Attempting to find next available /{cidr_block_size} in View: {network_view} | Supernet: {supernet_ip}...")
    response = None # Initialize response to None
    try:
        response = session.get(wapi_url, params=params, timeout=30)
        response.raise_for_status()  # Will raise an HTTPError for bad responses (4xx or 5xx)
        data = response.json()

        # When asking for next available network this way, Infoblox often returns a list of strings (the CIDRs)
        # or a list of network objects.
        if data and isinstance(data, list) and len(data) > 0:
            if isinstance(data[0], str): # Case 1: List of CIDR strings
                proposed_network = data[0]
                logger.info(f"SUCCESS: Proposed network CIDR string found: {proposed_network}")
                return proposed_network
            elif isinstance(data[0], dict) and 'network' in data[0]: # Case 2: List of network objects
                proposed_network = data[0]['network']
                logger.info(f"SUCCESS: Proposed network object found, CIDR: {proposed_network}")
                return proposed_network
            else:
                logger.error(f"ERROR: Unexpected item type in list from Infoblox: {type(data[0])}")
                logger.error(f"Raw Infoblox Response: {json.dumps(data, indent=2)}")
                return None
        else:
            logger.error(f"ERROR: No available network found or empty list in response from Infoblox for {supernet_ip} with /{cidr_block_size}.")
            logger.error(f"Raw Infoblox Response (if any data): {json.dumps(data, indent=2) if data else 'No data in response'}")
            return None

    except requests.exceptions.HTTPError as http_err:
        logger.error(f"ERROR: Infoblox API request failed (HTTPError) during next_available_network lookup: {http_err}")
        if http_err.response is not None:
            logger.error(f"Infoblox Response Content: {http_err.response.text}")
        return None
    except requests.exceptions.RequestException as e: # Catches other request-related errors (DNS, connection, etc.)
        logger.error(f"ERROR: Infoblox API request failed (RequestException) during next_available_network lookup: {e}")
        if response is not None:
            logger.error(f"Infoblox Response Text (if available): {response.text}")
        return None
    except json.JSONDecodeError:
        logger.error(f"ERROR: Failed to parse JSON response from Infoblox for next_available_network.")
        if response is not None:
             logger.error(f"Infoblox Raw Response causing JSONDecodeError: {response.text}")
        return None

def reserve_cidr(session, infoblox_url, proposed_subnet, network_view, subnet_name, site_code):
    """
    Performs the actual CIDR reservation (network creation) in Infoblox.
    """
    # Correctly construct the WAPI URL using the full base URL from infoblox_url
    wapi_url = f"{infoblox_url.rstrip('/')}/network"

    logger.info(f"DEBUG SCRIPT: Inside reserve_cidr:")
    logger.info(f"DEBUG SCRIPT:   infoblox_url (raw from secret/arg) = '{infoblox_url}'")
    logger.info(f"DEBUG SCRIPT:   constructed wapi_url = '{wapi_url}'")
    logger.info(f"DEBUG SCRIPT:   proposed_subnet = '{proposed_subnet}'")
    logger.info(f"DEBUG SCRIPT:   network_view = '{network_view}'")
    logger.info(f"DEBUG SCRIPT:   subnet_name (comment) = '{subnet_name}'")
    logger.info(f"DEBUG SCRIPT:   site_code = '{site_code}'")

    payload = {
        "network": proposed_subnet,
        "network_view": network_view,
        "comment": subnet_name,
        "extattrs": {
            "Site Code": {"value": site_code}
        }
    }
    logger.info(f"DEBUG SCRIPT: Payload for CIDR reservation: {json.dumps(payload, indent=2)}")

    logger.info(f"Attempting to reserve CIDR: {proposed_subnet} in network view: {network_view}...")
    response = None # Initialize response to None
    try:
        response = session.post(wapi_url, json=payload, timeout=30)
        response.raise_for_status() # Will raise an HTTPError for bad responses (4xx or 5xx)
        data = response.json() # Infoblox usually returns the _ref of the created object
        logger.info(f"SUCCESS: Successfully reserved CIDR: {proposed_subnet}. Infoblox Ref: {data}")
        return True
    except requests.exceptions.HTTPError as http_err:
        logger.error(f"ERROR: Infoblox API request failed (HTTPError) during CIDR reservation: {http_err}")
        if http_err.response is not None:
            logger.error(f"Infoblox Response Content: {http_err.response.text}")
        return False
    except requests.exceptions.RequestException as e:
        logger.error(f"ERROR: Infoblox API request failed (RequestException) during CIDR reservation: {e}")
        if response is not None:
            logger.error(f"Infoblox Response Text (if available): {response.text}")
        return False
    except json.JSONDecodeError:
        logger.error(f"ERROR: Failed to parse JSON response from Infoblox during CIDR reservation.")
        if response is not None:
            logger.error(f"Infoblox Raw Response causing JSONDecodeError: {response.text}")
        return False

def get_supernet_info(session, infoblox_url, supernet_ip, network_view):
    """
    Fetches information about the supernet. This function is conceptual/placeholder.
    Actual implementation would query Infoblox for supernet details.
    """
    logger.info(f"DEBUG SCRIPT: Simulating supernet info for {supernet_ip} in view {network_view}. Real implementation would query Infoblox.")
    # Example: You might want to query the supernet object and get its utilization or other attributes.
    # For now, it just returns a descriptive string.
    return f"Information for supernet {supernet_ip} in network view {network_view} (simulation)"

def validate_inputs(network_view, supernet_ip, subnet_name, cidr_block_size_str):
    """Performs basic input validations."""
    if not all([network_view, supernet_ip, subnet_name, str(cidr_block_size_str)]): # Check if any are None or empty
        logger.error("Validation Error: All inputs (network_view, supernet_ip, subnet_name, cidr_block_size) are required and cannot be empty.")
        return False
    
    try:
        cidr_block_size = int(cidr_block_size_str)
        if not (1 <= cidr_block_size <= 32): # Typical range for IPv4 CIDR prefix
            logger.error(f"Validation Error: CIDR block size must be an integer between 1 and 32. Received: {cidr_block_size}")
            return False
    except ValueError:
        logger.error(f"Validation Error: CIDR block size must be a valid integer. Received: {cidr_block_size_str}")
        return False
        
    try:
        ipaddress.ip_network(supernet_ip, strict=False)
    except ValueError:
        logger.error(f"Validation Error: Invalid Supernet IP format: {supernet_ip}")
        return False
    if not subnet_name.strip(): # Checks if subnet_name is not just whitespace
        logger.error("Validation Error: Subnet name cannot be empty or just whitespace.")
        return False
    return True

def main():
    parser = argparse.ArgumentParser(description="Infoblox CIDR Reservation Workflow Script")
    parser.add_argument("action", choices=["dry-run", "apply"], help="Action to perform: dry-run or apply")
    parser.add_argument("--infoblox-url", required=True, help="Infoblox WAPI URL (e.g., https://infoblox.example.com/wapi/vX.X)")
    parser.add_argument("--network-view", required=True, help="Infoblox Network View/Container")
    parser.add_argument("--supernet-ip", required=True, help="Supernet IP from which to reserve")
    parser.add_argument("--subnet-name", required=True, help="Name for the new subnet (used as comment)")
    parser.add_argument("--cidr-block-size", type=int, required=True, help="CIDR block size (e.g., 26 for /26)")
    parser.add_argument("--site-code", required=False, default="GCP", help="Site Code (default: GCP)")
    # For 'apply' action, these are passed from 'dry-run' job outputs
    parser.add_argument("--proposed-subnet", help="Proposed subnet from dry-run (for apply action)")
    parser.add_argument("--supernet-after-reservation", help="Supernet status after reservation (from dry-run, currently simulated)")

    args = parser.parse_args()

    infoblox_username = os.environ.get("INFOBLOX_USERNAME")
    infoblox_password = os.environ.get("INFOBLOX_PASSWORD")

    if not infoblox_username or not infoblox_password:
        logger.error("Infoblox username or password not found in environment variables.")
        logger.error("Ensure INFOBLOX_USERNAME and INFOBLOX_PASSWORD are set.")
        exit(1)

    if not validate_inputs(args.network_view, args.supernet_ip, args.subnet_name, args.cidr_block_size):
        exit(1)

    session = get_infoblox_session(args.infoblox_url, infoblox_username, infoblox_password)
    if not session:
        logger.error("Failed to establish Infoblox session. Exiting.")
        exit(1)

    if args.action == "dry-run":
        logger.info("\n--- Performing Dry Run ---")
        logger.info(f"DEBUG SCRIPT: Dry-run inputs - Network View: {args.network_view}, Supernet IP: {args.supernet_ip}, Subnet Name: {args.subnet_name}, CIDR Size: {args.cidr_block_size}")
        
        proposed_subnet = find_next_available_cidr(
            session, args.infoblox_url, args.network_view, args.supernet_ip, args.cidr_block_size
        )

        if proposed_subnet:
            logger.info(f"DRY RUN: Proposed Subnet to Reserve: {proposed_subnet}")
            logger.info(f"DRY RUN: Network View: {args.network_view}")
            logger.info(f"DRY RUN: Supernet IP: {args.supernet_ip}")
            logger.info(f"DRY RUN: Subnet Name (Comment): {args.subnet_name}")
            logger.info(f"DRY RUN: CIDR Block Size: /{args.cidr_block_size}")
            logger.info(f"DRY RUN: Site Code: {args.site_code}")

            supernet_after_reservation = get_supernet_info( # This is still the simulated function
                session, args.infoblox_url, args.supernet_ip, args.network_view
            )
            logger.info(f"DRY RUN: Supernet Status (after hypothetical reservation): {supernet_after_reservation}")

            # Setting output for GitHub Actions
            # Consider replacing with $GITHUB_OUTPUT method if runner supports it well and you prefer.
            print(f"::set-output name=proposed_subnet::{proposed_subnet}")
            print(f"::set-output name=supernet_after_reservation::{supernet_after_reservation}")
            logger.info("\nDry run completed successfully. Review the proposed changes before proceeding to apply.")
        else:
            logger.error("DRY RUN FAILED: Could not determine a proposed subnet. Check Infoblox connectivity, available space, and WAPI logs.")
            exit(1)

    elif args.action == "apply":
        logger.info("\n--- Performing Apply ---")
        if not args.proposed_subnet: # Removed check for supernet_after_reservation as it's simulated
            logger.error("Apply FAILED: Missing --proposed-subnet from dry run. This indicates a problem with job chaining or dry-run success.")
            exit(1)
        
        logger.info(f"DEBUG SCRIPT: Apply inputs - Proposed Subnet: {args.proposed_subnet}, Network View: {args.network_view}, Subnet Name: {args.subnet_name}, Site Code: {args.site_code}")

        logger.info(f"APPLY: Reserving proposed subnet: {args.proposed_subnet}")
        # Other details for apply log
        logger.info(f"APPLY: Network View: {args.network_view}")
        logger.info(f"APPLY: Supernet IP (parent): {args.supernet_ip}") # Original supernet
        logger.info(f"APPLY: Subnet Name (Comment): {args.subnet_name}")
        logger.info(f"APPLY: Site Code: {args.site_code}")


        success = reserve_cidr(
            session, args.infoblox_url, args.proposed_subnet, args.network_view, args.subnet_name, args.site_code
        )

        if success:
            logger.info(f"APPLY: Successfully reserved CIDR: {args.proposed_subnet}")
            # The supernet_after_reservation is from dry-run and currently simulated, so just log it as passed.
            logger.info(f"APPLY: Supernet status from dry-run (simulated): {args.supernet_after_reservation}")
            logger.info("\nApply completed successfully. Verify the changes in Infoblox.")
        else:
            logger.error(f"APPLY FAILED: Could not reserve CIDR: {args.proposed_subnet}. Check Infoblox logs for details.")
            exit(1)

if __name__ == "__main__":
    main()
