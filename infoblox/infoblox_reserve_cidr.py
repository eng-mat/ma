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
    session.verify = False # For production, set to True and manage certs
    return session

def find_next_available_cidr(session, infoblox_url, network_view, supernet_ip, cidr_block_size):
    """
    Finds the next available CIDR block within the specified supernet and network view.
    Uses network_container and _return_type="nextavailablenet".
    """
    wapi_url = f"{infoblox_url.rstrip('/')}/network"

    logger.info(f"DEBUG SCRIPT: Inside find_next_available_cidr:")
    logger.info(f"DEBUG SCRIPT:   infoblox_url (raw) = '{infoblox_url}'")
    logger.info(f"DEBUG SCRIPT:   constructed wapi_url = '{wapi_url}'")
    logger.info(f"DEBUG SCRIPT:   network_view = '{network_view}'")
    logger.info(f"DEBUG SCRIPT:   supernet_ip (as network_container) = '{supernet_ip}'")
    logger.info(f"DEBUG SCRIPT:   cidr_block_size (for new subnet) = '{cidr_block_size}'")

    params = {
        "network_view": network_view,
        "network_container": supernet_ip, # Use supernet_ip as the container/parent
        "cidr": cidr_block_size,          # The desired prefix of the new network
        "_return_type": "nextavailablenet", # Ask for the next available network(s)
        "_return_fields+": "network",     # We want the network CIDR string primarily
        "num": 1                          # We need one such network
    }
    logger.info(f"DEBUG SCRIPT: Params dictionary for next available network: {json.dumps(params, indent=2)}")

    logger.info(f"Attempting to find next available /{cidr_block_size} in View: {network_view} from Container: {supernet_ip}...")
    response = None
    try:
        response = session.get(wapi_url, params=params, timeout=30)
        response.raise_for_status()
        data = response.json()

        # For _return_type=nextavailablenet, Infoblox typically returns a list of CIDR strings
        if data and isinstance(data, list) and len(data) > 0:
            if isinstance(data[0], str): # Expected: List of CIDR strings
                proposed_network = data[0]
                logger.info(f"SUCCESS: Proposed network CIDR string found: {proposed_network}")
                return proposed_network
            # Less common for _return_type=nextavailablenet, but handle if it returns objects
            elif isinstance(data[0], dict) and 'network' in data[0]:
                 proposed_network = data[0]['network']
                 logger.info(f"SUCCESS: Proposed network object found, CIDR: {proposed_network}")
                 return proposed_network
            else:
                logger.error(f"ERROR: Unexpected item type in list from Infoblox: {type(data[0])}")
                logger.error(f"Raw Infoblox Response: {json.dumps(data, indent=2)}")
                return None
        else:
            logger.error(f"ERROR: No available network found or empty list in response from Infoblox.")
            logger.error(f"Raw Infoblox Response: {json.dumps(data, indent=2) if data else 'No data in response'}")
            return None
            
    except requests.exceptions.HTTPError as http_err:
        logger.error(f"ERROR: Infoblox API request failed (HTTPError): {http_err}")
        if http_err.response is not None:
            logger.error(f"Infoblox Response Content: {http_err.response.text}") # This will show the exact error from Infoblox
        return None
    except requests.exceptions.RequestException as e:
        logger.error(f"ERROR: Infoblox API request failed (RequestException): {e}")
        if response is not None:
            logger.error(f"Infoblox Response Text (if available): {response.text}")
        return None
    except json.JSONDecodeError:
        logger.error(f"ERROR: Failed to parse JSON response from Infoblox.")
        if response is not None:
             logger.error(f"Infoblox Raw Response: {response.text}")
        return None

def reserve_cidr(session, infoblox_url, proposed_subnet, network_view, subnet_name, site_code):
    """
    Performs the actual CIDR reservation (network creation) in Infoblox.
    """
    wapi_url = f"{infoblox_url.rstrip('/')}/network"

    logger.info(f"DEBUG SCRIPT: Inside reserve_cidr:")
    logger.info(f"DEBUG SCRIPT:   infoblox_url (raw) = '{infoblox_url}'")
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
    response = None
    try:
        response = session.post(wapi_url, json=payload, timeout=30)
        response.raise_for_status()
        data = response.json()
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
            logger.error(f"Infoblox Raw Response: {response.text}")
        return False

def get_supernet_info(session, infoblox_url, supernet_ip, network_view):
    logger.info(f"DEBUG SCRIPT: Simulating supernet info for {supernet_ip} in view {network_view}.")
    return f"Information for supernet {supernet_ip} in network view {network_view} (simulation)"

def validate_inputs(network_view, supernet_ip, subnet_name, cidr_block_size_str):
    if not all([network_view, supernet_ip, subnet_name, str(cidr_block_size_str)]):
        logger.error("Validation Error: All inputs (network_view, supernet_ip, subnet_name, cidr_block_size) are required.")
        return False
    try:
        cidr_block_size = int(cidr_block_size_str)
        if not (1 <= cidr_block_size <= 32):
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
    if not subnet_name.strip():
        logger.error("Validation Error: Subnet name cannot be empty or just whitespace.")
        return False
    return True

def main():
    parser = argparse.ArgumentParser(description="Infoblox CIDR Reservation Workflow Script")
    parser.add_argument("action", choices=["dry-run", "apply"], help="Action to perform: dry-run or apply")
    parser.add_argument("--infoblox-url", required=True, help="Infoblox WAPI URL (e.g., https://infoblox.example.com/wapi/vX.X)")
    parser.add_argument("--network-view", required=True, help="Infoblox Network View/Container")
    parser.add_argument("--supernet-ip", required=True, help="Supernet IP from which to reserve (used as network_container)")
    parser.add_argument("--subnet-name", required=True, help="Name for the new subnet (used as comment)")
    parser.add_argument("--cidr-block-size", type=int, required=True, help="CIDR block size (e.g., 26 for /26)")
    parser.add_argument("--site-code", required=False, default="GCP", help="Site Code (default: GCP)")
    parser.add_argument("--proposed-subnet", help="Proposed subnet from dry-run (for apply action)")
    parser.add_argument("--supernet-after-reservation", help="Supernet status after reservation (from dry-run, simulated)")

    args = parser.parse_args()

    infoblox_username = os.environ.get("INFOBLOX_USERNAME")
    infoblox_password = os.environ.get("INFOBLOX_PASSWORD")

    if not infoblox_username or not infoblox_password:
        logger.error("Infoblox username or password not found in environment variables.")
        exit(1)

    if not validate_inputs(args.network_view, args.supernet_ip, args.subnet_name, args.cidr_block_size):
        exit(1)

    session = get_infoblox_session(args.infoblox_url, infoblox_username, infoblox_password)
    if not session:
        logger.error("Failed to establish Infoblox session.")
        exit(1)

    if args.action == "dry-run":
        logger.info("\n--- Performing Dry Run ---")
        logger.info(f"DEBUG SCRIPT: Dry-run inputs - Network View: {args.network_view}, Supernet IP (Container): {args.supernet_ip}, Subnet Name: {args.subnet_name}, CIDR Size: {args.cidr_block_size}")
        
        proposed_subnet = find_next_available_cidr(
            session, args.infoblox_url, args.network_view, args.supernet_ip, args.cidr_block_size
        )

        if proposed_subnet:
            logger.info(f"DRY RUN: Proposed Subnet to Reserve: {proposed_subnet}")
            # ... (other dry run log messages) ...
            supernet_after_reservation = get_supernet_info(
                session, args.infoblox_url, args.supernet_ip, args.network_view
            )
            logger.info(f"DRY RUN: Supernet Status (simulated): {supernet_after_reservation}")
            print(f"::set-output name=proposed_subnet::{proposed_subnet}")
            print(f"::set-output name=supernet_after_reservation::{supernet_after_reservation}")
            logger.info("\nDry run completed successfully.")
        else:
            logger.error("DRY RUN FAILED: Could not determine a proposed subnet.")
            exit(1)

    elif args.action == "apply":
        logger.info("\n--- Performing Apply ---")
        if not args.proposed_subnet:
            logger.error("Apply FAILED: Missing --proposed-subnet from dry run.")
            exit(1)
        
        logger.info(f"DEBUG SCRIPT: Apply inputs - Proposed Subnet: {args.proposed_subnet}, Network View: {args.network_view}, Subnet Name: {args.subnet_name}")
        # ... (other apply log messages) ...
        success = reserve_cidr(
            session, args.infoblox_url, args.proposed_subnet, args.network_view, args.subnet_name, args.site_code
        )
        if success:
            logger.info(f"APPLY: Successfully reserved CIDR: {args.proposed_subnet}")
            logger.info("\nApply completed successfully.")
        else:
            logger.error(f"APPLY FAILED: Could not reserve CIDR: {args.proposed_subnet}.")
            exit(1)

if __name__ == "__main__":
    main()
