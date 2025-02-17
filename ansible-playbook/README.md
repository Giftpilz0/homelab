# Ansible VM Configuration

This Ansible playbook automates the configuration of previously provisioned virtual machines (VMs) using Terraform.

## Project Structure

The project directory structure is as follows:

```
├── ansible.cfg
├── inventory
│   ├── group_vars
│   │   ├── container.yml
│   │   ├── k3s.yml
│   │   ├── lb.yml
│   │   ├── monitoring.yml
│   │   ├── nfs.yml
│   │   └── server.yml
│   └── hosts.yml
└── play.yml
```

- **ansible.cfg**: Ansible configuration file that specifies settings for the Ansible runtime environment.
- **inventory**: Directory containing inventory files and group variables.
  - **group_vars**: Directory containing YAML files with variables specific to different groups of hosts.
    - **container.yml**: Variables used to configure the Podman VM.
    - **k3s.yml**: Variables used to configure Kubernetes nodes.
    - **lb.yml**: Variables used to configure the Loadbalancer/Jumphost VM.
    - **monitoring.yml**: Variables used to configure the Monitoring VM.
    - **nfs.yml**: Variables used to configure the NFS Storage VM.
    - **server.yml**: Variables used to configure common settings.
  - **hosts.yml**: Inventory file that defines the hosts and groups that Ansible will manage.
- **play.yml**: Ansible playbook file that defines tasks to run on managed hosts.

## Getting Started

To use this Ansible project to configure previously provisioned VMs:

1. Ensure that you have Ansible installed on your local machine. You can install Ansible via your package manager or follow the instructions on the [official Ansible documentation](https://docs.ansible.com/ansible/latest/installation_guide/index.html).
1. Review and adjust the inventory files in the 'inventory' directory. Ensure that hosts are correctly defined in the 'hosts.yml' inventory file and that group variables in the 'group_vars' directory are set appropriately for your VMs.
1. Review and adjust the 'play.yml' playbook file to define the desired configuration tasks for your VMs.
1. Execute the Ansible playbook to apply the configuration changes to the VMs:
   ```bash
   ansible-playbook play.yml
   ```
