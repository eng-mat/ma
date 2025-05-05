import requests
import json
import ipaddress
import sys
import os

def get_infoblox_data(api_url, username, password, verify_ssl=True):
    """
    Establishes a session with the Infoblox API and retrieves common data.

    Args:
        api_url (str): The base URL of the Infoblox API.
        username (str): The Infoblox API username.
        password (str): The Infoblox API password.
        verify_ssl (bool, optional): Whether to verify SSL certificates. Defaults to True.

    Returns:
        requests.Session: A session object connected to the Infoblox API, or None on error.
    """
    session = requests.Session()
    session.auth = (username, password)
    session.verify = verify_ssl
    session.headers.update({'Content-Type': 'application/json'})
    try:
        response = session.get(f"{api_url}/wapi/v2.11", timeout=10)  # Use a specific WAPI version
        response.raise_for_status()
        return session
    except requests.exceptions.RequestException as e:
        print(f"Error connecting to Infoblox API: {e}")
        return None

def get_network_view_ref(session, network_view_name):
    """
    Retrieves the object reference for a given Infoblox Network View.

    Args:
        session (requests.Session): The Infoblox API session.
        network_view_name (str): The name of the Network View.

    Returns:
        str: The object reference of the Network View, or None if not found.
    """
    try:
        response = session.get(f"/wapi/v2.11/networkview?name={network_view_name}", timeout=10)
        response.raise_for_status()
        data = response.json()
        if data:
            return data[0]['_ref']
        else:
            print(f"Network View '{network_view_name}' not found.")
            return None
    except requests.exceptions.RequestException as e:
        print(f"Error retrieving Network View: {e}")
        return None

def get_supernet_utilization(session, supernet_ref):
    """
    Calculates the utilization of a supernet.

    Args:
        session (requests.Session): The Infoblox API session.
        supernet_ref (str): The object reference of the supernet.

    Returns:
        float: The utilization percentage (0-100), or None on error.
    """
    try:
        response = session.get(f"/wapi/v2.11/{supernet_ref}?_fields=utilization", timeout=10)
        response.raise_for_status()
        data = response.json()
        if 'utilization' in data:
            return data['utilization']
        else:
            return None
    except requests.exceptions.RequestException as e:
        print(f"Error retrieving supernet utilization: {e}")
        return None

def find_available_cidr(session, network_view_ref, supernet_cidr, prefix_length):
    """
    Finds an available CIDR within a supernet in Infoblox.

    Args:
        session (requests.Session): The Infoblox API session.
        network_view_ref (str): The object reference of the Network View.
        supernet_cidr (str): The CIDR of the supernet.
        prefix_length (int): The desired prefix length of the subnet.

    Returns:
        str: The available CIDR, or None if no CIDR is available.
    """
    payload = {
        "network_view": network_view_ref,
        "supernet": supernet_cidr,
        "prefix": prefix_length,
    }
    try:
        response = session.post("/wapi/v2.11/network/available", json=payload, timeout=10)
        response.raise_for_status()
        data = response.json()
        if data and 'cidr' in data:
            return data['cidr']
        else:
            print(f"No available CIDR found in {supernet_cidr} with prefix length {prefix_length}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"Error finding available CIDR: {e}")
        return None

def reserve_cidr(session, network_view_ref, supernet_cidr, cidr, subnet_name):
    """
    Reserves a CIDR in Infoblox.

    Args:
        session (requests.Session): The Infoblox API session.
        network_view_ref (str): The object reference of the Network View.
        supernet_cidr (str): The CIDR of the supernet.
        cidr (str): The CIDR to reserve.
        subnet_name (str): The name/comment for the subnet.

    Returns:
        str: The object reference of the reserved network, or None on error.
    """

    network_address = str(ipaddress.ip_network(cidr, strict=False).network_address)
    prefix_length = ipaddress.ip_network(cidr, strict=False).prefixlen
    payload = {
        "network_view": network_view_ref,
        "network": network_address,
        "prefixlen": prefix_length,
        "comment": subnet_name,
    }

    try:
        response = session.post("/wapi/v2.11/network", json=payload, timeout=10)
        response.raise_for_status()
        data = response.json()
        if '_ref' in data:
            return data['_ref']
        else:
            print(f"Failed to reserve CIDR {cidr} in Infoblox.")
            return None
    except requests.exceptions.RequestException as e:
        print(f"Error reserving CIDR: {e}")
        return None

def delete_cidr(session, network_view_ref, cidr, subnet_name):
    """
    Deletes a CIDR reservation from Infoblox, using network view and comment.

    Args:
        session (requests.Session): The Infoblox API session.
        network_view_ref (str): The object reference of the Network View.
        cidr (str): The CIDR to delete.
        subnet_name (str): The name/comment of the subnet to delete.

    Returns:
        bool: True if the CIDR was deleted successfully, False otherwise.
    """
    try:
        # Find the network object by network address, prefix length, network view, and comment.
        network_address = str(ipaddress.ip_network(cidr, strict=False).network_address)
        prefix_length = ipaddress.ip_network(cidr, strict=False).prefixlen
        response = session.get(
            f"/wapi/v2.11/network?network={network_address}&prefixlen={prefix_length}&network_view={network_view_ref}&comment={subnet_name}", timeout=10
        )
        response.raise_for_status()
        data = response.json()

        if data:
            # Loop through the results and delete anyone
            for network_object in data:
                network_ref = network_object['_ref']
                delete_response = session.delete(f"/wapi/v2.11/{network_ref}", timeout=10)
                delete_response.raise_for_status()
                print(f"Deleted CIDR {cidr} with subnet name '{subnet_name}' from Infoblox.")
                return True
        else:
            print(f"CIDR {cidr} with subnet name '{subnet_name}' not found in Infoblox.")
            return False

    except requests.exceptions.RequestException as e:
        print(f"Error deleting CIDR: {e}")
        return False
    except Exception as e:
        print(f"Error: {e}")
        return False

def main():
    """
    Main function to parse arguments and perform IPAM operations.
    """
    if len(sys.argv) < 2:
        print("Usage: python infoblox_ipam.py <reserve|delete> ...")
        sys.exit(1)

    operation = sys.argv[1].lower()
    if operation not in ["reserve", "delete"]:
        print("Error: Operation must be 'reserve' or 'delete'.")
        sys.exit(1)

    # Load credentials from infoblox_creds.json
    try:
        with open("infoblox_creds.json", "r") as f:
            credentials = json.load(f)
            api_url = credentials["IB_API_URL"]
            username = credentials["IB_API_USERNAME"]
            password = credentials["IB_API_PASSWORD"]
            verify_ssl = credentials.get("IB_VERIFY_SSL", True)  # Default to True if not present
    except FileNotFoundError:
        print("Error: infoblox_creds.json file not found.  Make sure this file exists in the directory where you run the script.")
        sys.exit(1)
    except json.JSONDecodeError:
        print("Error: Invalid JSON in infoblox_creds.json file.")
        sys.exit(1)
    except KeyError as e:
        print(f"Error: Missing key in infoblox_creds.json: {e}")
        sys.exit(1)

    session = get_infoblox_data(api_url, username, password, verify_ssl)
    if session is None:
        sys.exit(1)

    if operation == "reserve":
        if len(sys.argv) != 6:
            print("Usage: python infoblox_ipam.py reserve <network_view> <supernet_cidr> <cidr_prefix> <subnet_name>")
            sys.exit(1)
        network_view_name = sys.argv[2]
        supernet_cidr = sys.argv[3]
        cidr_prefix = int(sys.argv[4])
        subnet_name = sys.argv[5]

        network_view_ref = get_network_view_ref(session, network_view_name)
        if network_view_ref is None:
            sys.exit(1)

        available_cidr = find_available_cidr(session, network_view_ref, supernet_cidr, cidr_prefix)
        if available_cidr:
            supernet_ref = "" # Placeholder, to avoid errors.
            try:
                response = session.get(f"/wapi/v2.11/network?network={supernet_cidr}&network_view={network_view_ref}", timeout=10)
                response.raise_for_status()
                supernet_data = response.json()
                if supernet_data:
                    supernet_ref = supernet_data[0]['_ref']
            except requests.exceptions.RequestException as e:
                print(f"Error retrieving supernet ref: {e}")

            supernet_utilization = get_supernet_utilization(session, supernet_ref)

            print(f"Found available CIDR: {available_cidr}")
            print(f"Supernet CIDR: {supernet_cidr}")
            print(f"Subnet Name: {subnet_name}")
            if supernet_utilization is not None:
                print(f"Supernet Utilization: {supernet_utilization:.2f}%")
            else:
                print("Supernet Utilization: N/A")
            # Write the outputs to files for consumption by later GitHub Actions steps
            with open("reserved_cidr.txt", "w") as f:
                f.write(available_cidr)
            with open("supernet_cidr.txt", "w") as f:
                f.write(supernet_cidr)
            with open("subnet_name.txt", "w") as f:
                f.write(subnet_name)
            if supernet_utilization is not None:
                with open("supernet_utilization.txt", "w") as f:
                    f.write(str(supernet_utilization))

            ref = reserve_cidr(session, network_view_ref, supernet_cidr, available_cidr, subnet_name)
            if ref:
                print(f"Successfully reserved CIDR {available_cidr} in Infoblox.  Ref: {ref}")
            else:
                print(f"Failed to reserve CIDR {available_cidr} in Infoblox.")
                sys.exit(1)
        else:
            print("Error: No available CIDR found.")
            sys.exit(1)

    elif operation == "delete":
        if len(sys.argv) != 5:
            print("Usage: python infoblox_ipam.py delete <network_view> <cidr_to_delete> <subnet_name>")
            sys.exit(1)
        network_view_name = sys.argv[2]
        cidr_to_delete = sys.argv[3]
        subnet_name = sys.argv[4]

        network_view_ref = get_network_view_ref(session, network_view_name)
        if network_view_ref is None:
            sys.exit(1)

        if delete_cidr(session, network_view_ref, cidr_to_delete, subnet_name):
            print(f"Successfully deleted CIDR {cidr_to_delete} from Infoblox.")
        else:
            print(f"Failed to delete CIDR {cidr_to_delete} from Infoblox.")
            sys.exit(1)

    session.close()

if __name__ == "__main__":
    main()