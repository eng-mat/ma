import requests
import os
import argparse
import urllib3
import logging

urllib3.disable_warnings()

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s]: %(message)s')

INFOBLOX_URL = os.getenv('INFOBLOX_URL')
USERNAME = os.getenv('INFOBLOX_USER')
PASSWORD = os.getenv('INFOBLOX_PASS')

def extract_cidr(supernet_input):
    """Extracts CIDR from input like '10.10.10.2/12 Test-supernet'."""
    if not supernet_input or len(supernet_input.strip().split()) < 1:
        raise ValueError("❌ Invalid or missing supernet input. Expected format: 'CIDR Label'")
    return supernet_input.strip().split()[0]

def reserve_ip(network_view, supernet, cidr, subnet_name, dry_run):
    logging.info(f"📦 Starting reservation | View: {network_view} | Supernet: {supernet} | CIDR: {cidr} | Name: {subnet_name} | Dry-run: {dry_run}")

    if dry_run:
        logging.info("🧪 DRY-RUN mode enabled. No actual reservation made.")
        return

    payload = {
        "network_view": network_view,
        "network": f"func:nextavailablenetwork:{supernet},{cidr}",
        "comment": subnet_name,
        "extattrs": {"SiteCode": {"value": "GCP"}}
    }

    response = requests.post(f"{INFOBLOX_URL}/network", json=payload, auth=(USERNAME, PASSWORD), verify=False)
    logging.info(f"🔁 Infoblox Response Code: {response.status_code}")

    if response.status_code != 201:
        logging.error(f"❌ Reservation failed: {response.text}")
        raise Exception(f"Reservation failed: {response.text}")

    result = response.json()
    logging.info(f"✅ Reserved CIDR: {result['network']}")

def delete_reservation(network_view, cidr, subnet_name, dry_run):
    logging.info(f"🗑️ Starting deletion | View: {network_view} | CIDR: {cidr} | Name: {subnet_name} | Dry-run: {dry_run}")

    if dry_run:
        logging.info("🧪 DRY-RUN mode enabled. No actual deletion made.")
        return

    query = {"network_view": network_view, "network": cidr, "comment": subnet_name}
    response = requests.get(f"{INFOBLOX_URL}/network", params=query, auth=(USERNAME, PASSWORD), verify=False)

    if response.status_code != 200 or not response.json():
        logging.error(f"❌ Reservation not found: {response.text}")
        raise Exception(f"Reservation not found: {response.text}")

    network_ref = response.json()[0]['_ref']
    del_response = requests.delete(f"{INFOBLOX_URL}/{network_ref}", auth=(USERNAME, PASSWORD), verify=False)

    if del_response.status_code != 200:
        logging.error(f"❌ Deletion failed: {del_response.text}")
        raise Exception(f"Deletion failed: {del_response.text}")

    logging.info(f"✅ Successfully deleted CIDR: {cidr}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Infoblox IPAM Automation")
    parser.add_argument("--action", required=True, choices=["reserve", "delete"])
    parser.add_argument("--network_view", required=True)
    parser.add_argument("--supernet", required=False)
    parser.add_argument("--cidr", required=False)
    parser.add_argument("--subnet_name", required=True)
    parser.add_argument("--dry_run", action="store_true")

    args = parser.parse_args()

    if args.action == "reserve":
        parsed_supernet = extract_cidr(args.supernet)
        reserve_ip(args.network_view, parsed_supernet, args.cidr, args.subnet_name, args.dry_run)
    elif args.action == "delete":
        delete_reservation(args.network_view, args.cidr, args.subnet_name, args.dry_run)
