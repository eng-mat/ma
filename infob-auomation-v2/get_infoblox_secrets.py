import os
from google.cloud import secretmanager

def get_infoblox_secrets(project_id, secret_name):
    """
    Retrieves Infoblox API credentials from Google Cloud Secret Manager.

    Args:
        project_id (str): The ID of the Google Cloud project.
        secret_name (str): The name of the secret containing the credentials.

    Returns:
        dict: A dictionary containing the Infoblox API credentials, or None on error.
    """
    client = secretmanager.SecretManagerServiceClient()
    secret_version_name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"

    try:
        response = client.access_secret_version(request={"name": secret_version_name})
        payload = response.payload.data.decode("UTF-8")
        return payload
    except Exception as e:
        print(f"Error accessing secret: {e}")
        return None

if __name__ == "__main__":
    # Example usage:
    project_id = os.environ.get("GCP_PROJECT_ID")
    secret_name = os.environ.get("INFOBLOX_SECRET_NAME")
    if not project_id or not secret_name:
        print("Error: GCP_PROJECT_ID and INFOBLOX_SECRET_NAME environment variables must be set.")
    else:
        credentials = get_infoblox_secrets(project_id, secret_name)
        if credentials:
            print(f"Retrieved credentials: {credentials}")
        else:
            print("Failed to retrieve credentials.")
