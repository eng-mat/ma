import requests
import json
import os
import argparse

def make_infoblox_request(method, endpoint, creds, data=None):
    """Makes a request to the Infoblox API."""
    auth = (creds.get("IB_API_USERNAME"), creds.get("IB_API_PASSWORD"))
    headers = {'Content-Type': 'application/json'}
    url = f"{creds.get('IB_API_URL')}{endpoint}"
    verify_ssl = creds.get("IB_VERIFY_SSL", "true").lower() == "true"
    try:
        response = requests.request(method, url, auth=auth, headers=headers, json=data, verify=verify_ssl)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        try:
            error_json = response.json()
            error_message = error_json.get('text', str(e))
        except (json.JSONDecodeError, AttributeError):
            error_message = str(e)
        raise Exception(f"Infoblox API error: {error_message}")

def find_available_cidr(network_view, supernet_cidr, prefix_length, subnet_name, creds):
    """Finds and reserves an available CIDR in Infoblox."""
    try:
        # Get the supernet object reference
        supernet_query_url = f"/network?network={supernet_cidr}&network_view={network_view}"
        supernet_data = make_infoblox_request("GET", supernet_query_url, creds)
        if not supernet_data:
            raise Exception(f"Supernet {supernet_cidr} not found in Network View {network_view}.")
        supernet_ref = supernet_data[0]['_ref']

        # Request an available network
        payload = {
            "network_container": supernet_ref,
            "prefix": prefix_length,
            "comment": subnet_name,
            "extattrs": {"SiteCode": {"value": "GCP"}}
        }
        reserved_data = make_infoblox_request("POST", "/network", creds, payload)
        return reserved_data['network']
    except Exception as e:
        with open("error.txt", "w") as f:
            f.write(str(e))
        return None

def delete_cidr_reservation(network_view, cidr_to_delete, subnet_name, creds):
    """Deletes a CIDR reservation from Infoblox."""
    try:
        # Find the network object to delete
        query_url = f"/network?network={cidr_to_delete}&network_view={network_view}&comment={subnet_name}"
        network_objects = make_infoblox_request("GET", query_url, creds)
        if not network_objects:
            raise Exception(f"No reservation found for CIDR {cidr_to_delete} with name '{subnet_name}' in Network View {network_view}.")
        if len(network_objects) > 1:
            raise Exception(f"Multiple reservations found for CIDR {cidr_to_delete} with name '{subnet_name}' in Network View {network_view}. Please be more specific.")

        delete_ref = network_objects[0]['_ref']
        make_infoblox_request("DELETE", f"/{delete_ref}", creds)
        return True
    except Exception as e:
        with open("error.txt", "w") as f:
            f.write(str(e))
        return False

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Interact with Infoblox IPAM.")
    subparsers = parser.add_subparsers(dest="command", help="Action to perform")

    # Subparser for reserving IP
    reserve_parser = subparsers.add_parser("reserve", help="Reserve a CIDR")
    reserve_parser.add_argument("--network-view", required=True, help="Infoblox Network View")
    reserve_parser.add_argument("--supernet", required=True, help="Supernet CIDR")
    reserve_parser.add_argument("--prefix", type=int, required=True, help="CIDR prefix length")
    reserve_parser.add_argument("--name", required=True, help="Subnet name (comment)")
    reserve_parser.add_argument("--creds-file", required=True, help="Path to the Infoblox credentials JSON file")

    # Subparser for deleting IP
    delete_parser = subparsers.add_parser("delete", help="Delete a CIDR reservation")
    delete_parser.add_argument("--network-view", required=True, help="Infoblox Network View")
    delete_parser.add_argument("--cidr", required=True, help="CIDR to delete")
    delete_parser.add_argument("--name", required=True, help="Subnet name (comment)")
    delete_parser.add_argument("--creds-file", required=True, help="Path to the Infoblox credentials JSON file")

    args = parser.parse_args()

    try:
        with open(args.creds_file, 'r') as f:
            infoblox_creds = json.load(f)
    except FileNotFoundError:
        print(f"Error: Credentials file not found at {args.creds_file}")
        os.sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: Invalid JSON format in {args.creds_file}")
        os.sys.exit(1)

    if args.command == "reserve":
        reserved_cidr = find_available_cidr(args.network_view, args.supernet, args.prefix, args.name, infoblox_creds)
        if reserved_cidr:
            with open("reserved_cidr.txt", "w") as f:
                f.write(reserved_cidr)
            print(f"Successfully reserved CIDR: {reserved_cidr}")
        else:
            print("Error during CIDR reservation. Check error.txt for details.")
    elif args.command == "delete":
        if delete_cidr_reservation(args.network_view, args.cidr, args.name, infoblox_creds):
            print("Successfully deleted CIDR reservation.")
        else:
            print("Error during CIDR deletion. Check error.txt for details.")
    else:
        print("Invalid command. Use 'reserve' or 'delete'.")