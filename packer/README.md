# Packer

Builds the AlmaLinux 10 VM template (VM 100) that OpenTofu clones.

## Usage

```bash
cd almalinux10/
sops exec-env secrets.sops.yaml 'packer build almalinux.pkr.hcl'
```
