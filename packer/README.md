# Packer Proxmox VM Template Creation

This packer project automates the creation of Proxmox virtual machine (VM) templates. It includes configurations to create an AlmaLinux VM template with cloud init support, facilitating rapid deployment of AlmaLinux-based VMs in Proxmox environments.

## Project Structure

The project directory structure is as follows:

```
├── almalinux10
│   ├── almalinux.pkr.hcl
│   └── http
│       └── almalinux.ks
```

- **almalinux10**: This directory contains configurations specific to building the AlmaLinux VM template.
  - **almalinux.pkr.hcl**: Packer configuration file for building the AlmaLinux VM template.
  - **http**: Directory containing any additional files needed during the deployment process.
    - **almalinux.ks**: Kickstart file used during the deployment of the AlmaLinux template VM.

## Getting Started

To use this packer project to create Proxmox VM templates, follow these steps:

1. Install packer on your local machine. You can download it from [packer.io](https://www.packer.io/downloads).
1. Navigate to the 'almalinux10' directory:
1. Optionally, modify the kickstart file 'almalinux.ks' in the 'http' directory if additional configurations are required.
1. Execute the packer build command to start building the AlmaLinux VM template:
   ```bash
   packer build almalinux.pkr.hcl
   ```
1. Packer will execute the build process, which involves creating a Proxmox VM, provisioning it with AlmaLinux, and preparing it as a template.
