# Infoblox IPAM Automation with GitHub Actions and GCP WIF

This project provides GitHub Actions workflows to automate the reservation and deletion of IP address ranges in Infoblox IPAM, leveraging Google Cloud Workload Identity Federation (WIF) for secure authentication and Google Cloud Secret Manager for storing Infoblox API credentials.

## Requirements

* **Google Cloud Setup:**

    * A Google Cloud Project.
    * Workload Identity Federation (WIF) configured between your GitHub organization and your GCP project.
    * A GCP service account with the following IAM roles:
        * `roles/iam.workloadIdentityUser` on the WIF pool.
        * `roles/secretmanager.secretAccessor` on the Google Cloud Secret Manager secret containing the Infoblox API credentials.
    * Google Cloud Secret Manager secret created to store Infoblox API credentials in JSON format. The expected format of this JSON file (e.g., `infoblox_creds.json`) is:

        ```json
        {
          "IB_API_URL": "your_infoblox_api_url",
          "IB_API_USERNAME": "your_infoblox_username",
          "IB_API_PASSWORD": "your_infoblox_password",
          "IB_VERIFY_SSL": "true" # Or "false" if needed
        }
        ```

        You can create the secret using the following gcloud command:

        ```bash
        gcloud secrets create INFOBLOX_API_CREDS \
            --replication-policy="automatic" \
            --data-file=infoblox_creds.json
        ```

        * `INFOBLOX_API_CREDS`: This is the name you choose for your secret in Secret Manager. You can change this name if you like (e.g., to `infoblox-credentials`).
        * `--replication-policy="automatic"`: This tells Secret Manager to automatically handle replication of your secret data.
        * `--data-file=infoblox_creds.json`: This specifies the path to your JSON file.  Ensure this file exists and contains your Infoblox API credentials in the JSON format specified above.

        The secret name (e.g., `INFOBLOX_API_CREDS`) should be stored in your GitHub repository's secrets as `INFOBLOX_SECRET_NAME`.

    * Ensure the Infoblox API is accessible from the environment where the Python scripts are run (likely the GitHub Actions runner or a GCP resource it interacts with).

* **GitHub Repository Setup:**

    * This repository with the provided workflow files (`.github/workflows/reserve_cidr.yml` and `.github/workflows/delete_cidr.yml`), the Python scripts (`get_infoblox_secrets.py` and `infoblox_ipam.py`), and the `requirements.txt` file.
    * The following GitHub repository secrets configured:
        * `GCP_WIF_POOL`: Your Workload Identity Pool ID.
        * `GCP_SVC_ACCOUNT`: The email address of the GCP service account.
        * `GCP_PROJECT_ID`: Your Google Cloud Project ID.
        * `INFOBLOX_SECRET_NAME`: The name of the secret you created in Google Cloud Secret Manager (e.g., `infoblox-api-creds`).

* **Infoblox Setup:**

    * Infoblox NIOS instance with the API enabled.
    * A user account with the necessary permissions to create, read, and delete network objects within the specified Network Views in Infoblox.
    * The Network Views and Supernets configured as described in your initial request.

## Usage

### Reserving a CIDR

1.  Navigate to the "Actions" tab in your GitHub repository.
2.  Select the "Reserve GCP CIDR in Infoblox" workflow.
3.  Click the "Run workflow" button.
4.  Provide the required inputs:

    * **Network View:** Select the Infoblox Network View.
    * **Supernet CIDR:** Enter the supernet CIDR to reserve from.
    * **CIDR Prefix:** Specify the desired CIDR prefix length (e.g., 26).
    * **Subnet Name:** Enter a descriptive name for the subnet (this will be used as the comment in Infoblox).
5.  Click "Run workflow".
6.  The workflow will:

    * Authenticate to GCP using WIF.
    * Retrieve Infoblox API credentials from Secret Manager.
    * Run the Python script to request an available CIDR in Infoblox.
    * Output the reserved CIDR and create a GitHub Issue for manual approval.
7.  **Approval Step:** Review the GitHub Issue. If the reservation is acceptable, comment "APPROVED" on the issue.
8.  Once approved, the workflow will proceed (the current implementation has a placeholder for your GCP subnet creation logic).

### Deleting a CIDR Reservation

1.  Navigate to the "Actions" tab in your GitHub repository.
2.  Select the "Delete GCP CIDR Reservation in Infoblox" workflow.
3.  Click the "Run workflow" button.
4.  Provide the required inputs:

    * **Network View:** Select the Infoblox Network View.
    * **CIDR to delete:** Enter the exact CIDR you want to delete (e.g., `10.20.30.0/26`).
    * **Subnet Name:** Enter the subnet name (the comment used when the CIDR was reserved).
5.  Click "Run workflow".
6.  The workflow will:

    * Authenticate to GCP using WIF.
    * Retrieve Infoblox API credentials from Secret Manager.
    * Run the Python script to delete the specified CIDR reservation in Infoblox.
    * Create a GitHub Issue for manual approval.
7.  **Approval Step:** Review the GitHub Issue. If the deletion is acceptable, comment "APPROVED" on the issue.
8.  Once approved, the workflow will complete.

## Next Steps

* Integrate the "Proceed with GCP Subnet Creation" step in the `reserve_cidr.yml` workflow with your existing GitHub Actions workflow that creates and attaches subnets in GCP. You can use the `steps.output_cidr.outputs.RESERVED_CIDR` and `github.event.inputs.subnet_name` variables.
* Consider adding more robust error handling and logging within the Python scripts.
* Explore other ways to trigger these workflows (e.g., based on events in your GCP environment).
