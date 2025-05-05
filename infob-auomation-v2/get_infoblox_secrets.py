import os
import json
from google.cloud import secretmanager
from google.oauth2 import service_account

def access_secret_version(project_id, secret_id):
    """Access the latest version of a secret."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("utf-8")

if __name__ == "__main__":
    if len(os.sys.argv) != 3:
        print("Usage: python get_infoblox_secrets.py <gcp_project_id> <infoblox_secret_name>")
        os.sys.exit(1)

    project_id = os.sys.argv[1]
    secret_name = os.sys.argv[2]

    try:
        secret_value = access_secret_version(project_id, secret_name)
        print(secret_value)
    except Exception as e:
        print(f"Error accessing secret: {e}")
        os.sys.exit(1)