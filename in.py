import requests
import os
import argparse
import urllib3

urllib3.disable_warnings()

INFOBLOX_URL = "https://infoblox.example.com/wapi/v2.10"
USERNAME = os.getenv('INFOBLOX_USER')
PASSWORD = os.getenv('INFOBLOX_PASS')

def reserve_ip(network_view, supernet, cidr, subnet_name, dry_run):
    print(f"🔍 Dry-run: {dry_run}")
    print(f"Reserving IP with view={network_view}, supernet={supernet}, cidr={cidr}, name={subnet_name}")

    if dry_run:
        print("🧪 Dry-run enabled, no reservation made.")
        return

    url = f"{INFOBLOX_URL}/network"
    payload = {
        "network_view": network_view,
        "network": f"func:nextavailablenetwork:{supernet},{cidr}",
        "comment": subnet_name,
        "extattrs": {"SiteCode": {"value": "GCP"}}
    }

    response = requests.post(url, json=payload, auth=(USERNAME, PASSWORD), verify=False)
    if response.status_code != 201:
        raise Exception(f"Reservation failed: {response.text}")

    network_result = response.json()
    print(f"✅ Reserved CIDR: {network_result['network']}")

def delete_reservation(network_view, cidr, subnet_name, dry_run):
    print(f"🔍 Dry-run: {dry_run}")
    print(f"Deleting IP with view={network_view}, cidr={cidr}, name={subnet_name}")

    if dry_run:
        print("🧪 Dry-run enabled, no deletion performed.")
        return

    url = f"{INFOBLOX_URL}/network"
    params = {"network_view": network_view, "network": cidr, "comment": subnet_name}
    response = requests.get(url, params=params, auth=(USERNAME, PASSWORD), verify=False)
    if response.status_code != 200 or not response.json():
        raise Exception(f"Reservation not found: {response.text}")

    network_ref = response.json()[0]['_ref']
    del_response = requests.delete(f"{INFOBLOX_URL}/{network_ref}", auth=(USERNAME, PASSWORD), verify=False)

    if del_response.status_code != 200:
        raise Exception(f"Deletion failed: {del_response.text}")

    print(f"🗑️ Deleted reservation: {cidr}")

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
