# Proxmox VM Deployment with Terraform

This project uses Terraform to automate the deployment of a set of Proxmox virtual machines. The configuration files are organized under the 'nodes' directory and include definitions for various VMs and associated resources.

## Project Structure

The project directory structure is as follows:

```
├── nodes
│   ├── container.tf
│   ├── k3s-node1.tf
│   ├── k3s-node2.tf
│   ├── k3s-node3.tf
│   ├── lb1.tf
│   ├── lb2.tf
│   ├── monitoring.tf
│   ├── nfs.tf
│   └── provider.tf
```

- **nodes**: This directory contains Terraform configuration files for defining Proxmox VMs and their associated resources.
  - **container.tf**: Terraform configuration for the container VM.
  - **k3s-node1.tf**, **k3s-node2.tf**, **k3s-node3.tf**: Terraform configurations for Kubernetes nodes.
  - **lb1.tf**, **lb2.tf**: Terraform configurations for loadbalancer VM.
  - **monitoring.tf**: Terraform configuration for the monitoring VM.
  - **nfs.tf**: Terraform configuration for the NFS Storage VM.
  - **provider.tf**: Terraform provider configuration for Proxmox.

## Getting Started

1. Install Terraform on your local machine. You can download it from [terraform.io](https://www.terraform.io/downloads.html).
1. Navigate to the 'nodes' directory:
1. Initialize Terraform:
   ```bash
   terraform init
   ```
1. Review and customize the Terraform configuration files in the 'nodes' directory.
1. Plan the Terraform deployment to ensure everything is configured correctly:
   ```bash
   terraform plan
   ```
1. Apply the Terraform configuration to provision the Proxmox VMs:
   ```bash
   terraform apply
   ```
