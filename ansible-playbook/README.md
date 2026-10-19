# Ansible VM Configuration

This Ansible playbook automates the configuration of previously provisioned virtual machines using OpenTofu.

## Requirements

- [uv](https://docs.astral.sh/uv/) (installs the pinned Python, ansible-core and ansible-lint)
- [sops](https://github.com/getsops/sops) with access to the GPG key (decrypts `*.sops.yaml` vars on the fly)

## Getting Started

```bash
./run.sh                          # pick the inventory interactively
./run.sh container                # run one inventory
./run.sh container --limit forgejo.nixpi.de --tags x
./run.sh --skip-collections ...   # skip ansible-galaxy collection install
```

`run.sh` syncs the uv environment, installs the collections from `requirements.yaml`
into `.ansible/collections` and runs `inventories/<name>/playbook.yaml`.
The `giftpilz0.*` collections are loaded directly from `../ansible_collections`.

## Secrets

Inventory secrets live in `*.sops.yaml` files next to the plain vars and are loaded by
the `community.sops.sops` vars plugin. Edit them with `sops edit <file>`.

## Linting

```bash
uv run ansible-lint   # from the repository root: uv run --project ansible-playbook ansible-lint
```
