# Packer Proxmox VM Template Creation

This packer project automates the creation of Proxmox virtual machine templates. It includes configurations to create an AlmaLinux VM template with cloud init support.

## Getting Started

```bash
cd almalinux10/
sops edit sops-secret.yaml
sops exec-env sops-secret.yaml 'packer build almalinux.pkr.hcl'
```
