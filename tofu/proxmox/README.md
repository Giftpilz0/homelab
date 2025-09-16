# Proxmox VM Deployment with OpenTofu

This project uses OpenTofu to automate the deployment of a set of Proxmox virtual machines.

## Getting Started

1. Install OpenTofu on your local machine. You can download it from [opentofu.org](https://opentofu.org/docs/intro/install/).
1. Initialize OpenTofu:
   ```bash
   tofu init
   ```
1. Review and customize the OpenTofu configuration files.
1. Plan the OpenTofu deployment to ensure everything is configured correctly:
   ```bash
   tofu plan
   ```
1. Apply the OpenTofu configuration to provision the Proxmox VMs:
   ```bash
   tofu apply
   ```
