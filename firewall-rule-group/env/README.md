# Firewall Rule Group

This repository contains Terraform configurations for managing firewall rule groups. Below is an overview of the structure and purpose of the `env` and `modules` folders.

## Folder Structure

### `env`
The `env` folder contains environment-specific configurations. These files define how the firewall rule groups are deployed in different environments (e.g., dev, staging, production). Key components include:
- **Variables**: Define environment-specific values.
- **Backend Configurations**: Manage Terraform state for the environment.
- **Environment Overrides**: Customize module inputs for each environment.

### `modules`
The `modules` folder contains reusable Terraform modules for creating and managing firewall rule groups. Key components include:
- **Inputs**: Variables to customize the module behavior.
- **Resources**: Terraform resources for firewall rules and groups.
- **Outputs**: Exported values for use in other configurations.

## Usage
1. Navigate to the desired environment folder under `env`.
2. Update the `terraform.tfvars` file with environment-specific values.
3. Run Terraform commands to deploy or update the infrastructure:
    ```bash
    terraform init
    terraform plan
    terraform apply
    ```

## Contributing
Feel free to open issues or submit pull requests to improve the configurations.

## License
This project is licensed under the MIT License. See the `LICENSE` file for details.