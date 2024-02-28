# Homelab Configuration

This project serves as a configuration repository for my homelab setup. It includes infrastructure as code tools such as Ansible, Packer and Terraform to define and manage the components of my homelab environment.

## Project Structure

The project directory structure is as follows:

```
├── ansible-playbook
├── packer
└── terraform
```

- **ansible-playbook**: Directory containing Ansible playbooks and related files for configuring and managing the homelab infrastructure.
- **packer**: Directory containing packer configurations for building virtual machine templates used in the homelab environment.
- **terraform**: Directory containing Terraform configurations used to deploy and manage the Homelab infrastructure.

## Overview

- **Ansible**: Used to configure and manage the software and services running on the homelab nodes.
- **Packer**: Used to create virtual machine templates with pre-configured operating systems and software. The templates are used as base images for the Homelab nodes, enabling consistent and repeatable deployments.
- **Terraform**: Used to provision the Homelab infrastructure. Terraform configurations define the desired state of the virtual machine infrastructure.
