# Proxmox VM Deployment with OpenTofu

This project uses OpenTofu to automate the deployment of a set of Proxmox virtual machines. The configuration files are organized under the 'nodes' directory and include definitions for various VMs and associated resources.

## Project Structure

The project directory structure is as follows:

```
├── nodes
│   ├── container.tf
│   ├── k3s-node1.tf
│   ├── lb1.tf
│   ├── lb2.tf
│   └── provider.tf
```

- **nodes**: This directory contains OpenTofu configuration files for defining Proxmox VMs and their associated resources.
  - **container.tf**: OpenTofu configuration for the container VM.
  - **k3s-node1.tf**: OpenTofu configurations for Kubernetes nodes.
  - **lb1.tf**, **lb2.tf**: OpenTofu configurations for loadbalancer VM.
  - **provider.tf**: OpenTofu provider configuration for Proxmox.

## Getting Started

1. Install OpenTofu on your local machine. You can download it from [opentofu.org](https://opentofu.org/docs/intro/install/).
1. Navigate to the 'nodes' directory:
1. Initialize OpenTofu:
   ```bash
   tofu init
   ```
1. Review and customize the OpenTofu configuration files in the 'nodes' directory.
1. Plan the OpenTofu deployment to ensure everything is configured correctly:
   ```bash
   tofu plan
   ```
1. Apply the OpenTofu configuration to provision the Proxmox VMs:
   ```bash
   tofu apply
   ```
