# Ansible

Inventories and playbooks that configure the VMs. Run them with `just deploy` from the repository root.

| Inventory   | Configures                            |
| ----------- | ------------------------------------- |
| `container` | Services on all VMs                   |
| `backup`    | restic on all VMs, rest-server on pve |
| `proxmox`   | The pve host                          |

## Usage

```bash
just deploy                               # pick an inventory interactively
just deploy container --check             # dry run
just deploy container -l git.nixpi.de     # one host
just deploy --skip-collections container  # skip ansible-galaxy
```

`run.sh` installs the Python toolchain with uv and the external collections from `requirements.yaml`.
The `giftpilz0.*` collections are loaded from `../ansible_collections`.

Secrets are in `*.sops.yaml` files next to the plain vars. Ansible decrypts them when it runs.
