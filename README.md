# homelab

[![ci](https://github.com/Giftpilz0/homelab/actions/workflows/ci.yml/badge.svg)](https://github.com/Giftpilz0/homelab/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

My homelab as code: Proxmox VMs built with Packer and OpenTofu, configured with Ansible.

## Usage

```sh
just deploy                       # pick an inventory interactively
just deploy container --check     # dry run of one inventory
```

- `ansible_collections/giftpilz0/`: roles (container, general, kubernetes, misc, server), also used by my dotfiles
- `ansible-playbook/`: inventories and `run.sh` (behind `just deploy`)
- `packer/`: AlmaLinux 10 VM template
- `tofu/`: OpenTofu for the Proxmox VMs
- [RESTORE.md](RESTORE.md): restoring from the restic backups

## Development

Run `just` for all recipes and `just check` before committing. Conventions: [Giftpilz0/shared](https://github.com/Giftpilz0/shared).

## License

[MIT](LICENSE)
