import requests
import os
import argparse
import urllib3
import logging

urllib3.disable_warnings()

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s]: %(message)s')

INFOBLOX_URL = "https://infoblox.example.com/wapi/v2.10"
USERNAME = os.getenv('INFOBLOX_USER')
PASSWORD = os.getenv('INFOBLOX_PASS')

def reserve_ip(network_view, supernet, cidr, subnet_name, dry_run):
    logging.info(f"Starting reservation for view={network_view}, supernet={supernet}, cidr={cidr}, subnet={subnet_name}, dry-run={dry_run}")

    if dry_run:
        logging.info("[DRY-RUN] No reservation made.")
        return

    payload = {
        "network_view": network_view,
        "network": f"func:nextavailablenetwork:{supernet},{cidr}",
        "comment": subnet_name,
        "extattrs": {"SiteCode": {"value": "GCP"}}
    }

    logging.info(f"Payload sent: {payload}")

    response = requests.post(f"{INFOBLOX_URL}/network", json=payload, auth=(USERNAME, PASSWORD), verify=False)
    logging.info(f"Infoblox response status: {response.status_code}")

    if response.status_code != 201:
        logging.error(f"Reservation failed: {response.text}")
        raise Exception(f"Reservation failed: {response.text}")

    network_result = response.json()
    logging.info(f"✅ Reserved CIDR: {network_result['network']}")

def delete_reservation(network_view, cidr, subnet_name, dry_run):
    logging.info(f"Starting deletion for view={network_view}, cidr={cidr}, subnet={subnet_name}, dry-run={dry_run}")

    if dry_run:
        logging.info("[DRY-RUN] No deletion made.")
        return

    params = {"network_view": network_view, "network": cidr, "comment": subnet_name}
    response = requests.get(f"{INFOBLOX_URL}/network", params=params, auth=(USERNAME, PASSWORD), verify=False)

    logging.info(f"Search response status: {response.status_code}")

    if response.status_code != 200 or not response.json():
        logging.error(f"Reservation not found: {response.text}")
        raise Exception(f"Reservation not found: {response.text}")

    network_ref = response.json()[0]['_ref']
    logging.info(f"Deleting network ref: {network_ref}")

    del_response = requests.delete(f"{INFOBLOX_URL}/{network_ref}", auth=(USERNAME, PASSWORD), verify=False)
    logging.info(f"Deletion response status: {del_response.status_code}")

    if del_response.status_code != 200:
        logging.error(f"Deletion failed: {del_response.text}")
        raise Exception(f"Deletion failed: {del_response.text}")

    logging.info(f"🗑️ Successfully deleted reservation: {cidr}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Infoblox IPAM Automation")
    parser.add_argument("--action", required=True, choices=["reserve", "delete"])
    parser.add_argument("--network_view", required=True)
    parser.add_argument("--supernet")
    parser.add_argument("--cidr")
    parser.add_argument("--subnet_name", required=True)
    parser.add_argument("--dry_run", action="store_true")

    args = parser.parse_args()

    if args.action == "reserve":
        reserve_ip(args.network_view, args.supernet, args.cidr, args.subnet_name, args.dry_run)
    elif args.action == "delete":
        delete_reservation(args.network_view, args.cidr, args.subnet_name, args.dry_run)
