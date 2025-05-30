import argparse
import requests
import json
import ipaddress
import os
import logging

# Configure logging (ensure it's configured as you had it)
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s]: %(message)s')
logger = logging.getLogger(__name__)

# ... (get_infoblox_session function remains the same) ...
def get_infoblox_session(infoblox_url, username, password):
    """Establishes a session with Infoblox and handles authentication."""
    session = requests.Session()
    session.auth = (username, password)
    session.verify = False # InsecureRequestWarning will appear, known issue for now
    return session

def find_next_available_cidr(session, infoblox_url, network_view, supernet_ip, cidr_block_size):
    """
    Finds the next available CIDR block within the specified supernet and network view.
    """
    wapi_url = f"{infoblox_url}/wapi/v2.10/network"

    # V V V ADD THESE DEBUG LINES V V V
    logger.info(f"DEBUG SCRIPT: Inside find_next_available_cidr:")
    logger.info(f"DEBUG SCRIPT:   infoblox_url = '{infoblox_url}'")
    logger.info(f"DEBUG SCRIPT:   network_view = '{network_view}'")
    logger.info(f"DEBUG SCRIPT:   supernet_ip = '{supernet_ip}'") # Critical value to check
    logger.info(f"DEBUG SCRIPT:   cidr_block_size = '{cidr_block_size}'")
    # V V V END OF NEW DEBUG LINES V V V

    params = {
        "_return_fields+": "network,network_view,comment,extattrs",
        "network_view": network_view,
        "network": supernet_ip,  # This is where the supernet_ip is used
        "next_available_network": f"{cidr_block_size}"
    }

    # V V V ADD THIS DEBUG LINE V V V
    logger.info(f"DEBUG SCRIPT: Params dictionary being sent to Infoblox: {json.dumps(params, indent=2)}")
    # V V V END OF NEW DEBUG LINE V V V

    logger.info(f"Attempting to find next available /{cidr_block_size} in View: {network_view} | Supernet: {supernet_ip}...") # Your existing log
    try:
        response = session.get(wapi_url, params=params, timeout=30)
        response.raise_for_status()
        data = response.json()

        # ... (rest of your function)
# ... (rest of your script: reserve_cidr, get_supernet_info, validate_inputs, main) ...

# In your main() function, when calling find_next_available_cidr:
# You can also add a log before this call:
# logger.info(f"DEBUG SCRIPT: Calling find_next_available_cidr with supernet_ip='{args.supernet_ip}' from args")
# proposed_subnet = find_next_available_cidr(
# session, args.infoblox_url, args.network_view, args.supernet_ip, args.cidr_block_size
# )
