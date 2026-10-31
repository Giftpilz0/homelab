# Homelab

Proxmox VMs built with Packer and OpenTofu, configured with Ansible.

```
ansible_collections/giftpilz0/{container,general,server,misc,kubernetes}   roles (dotfiles also use general)
ansible-playbook/inventories/{container,backup,proxmox}         playbooks, hosts, vars
tofu/{proxmox,keycloak}                                                    OpenTofu projects
dns/records.conf                                                           hosts and service names, applied to the UDM
packer/almalinux10                                                         VM template
```

## Rules

- `just check` is the definition of done. Show its result.
- Commit only when asked, without a `Co-Authored-By` line. Never push.
- Encrypted files (`*.sops.yaml`, `state.tfstate.enc`) may be read. Never decrypt them or print decrypted values:
  no `sops`, `ansible-inventory`, `tofu show|output|state|console`, or `ansible-playbook --diff`.
- Plain state (`state.tfstate`, `.terraform/`) lies in `tofu/` while the user works on it. Search with `git grep`, which
  only sees tracked files, and exclude `*.enc`.
- The user runs anything that needs the GPG key with `! <command>`: `sops`, `tofu plan|apply`, `tofu/state-utils.sh`,
  `just dns`. New secrets go into a `*.sops.yaml` file, reference them by variable name.
- Ask before anything hard to undo on the hosts, such as deleting data or rotating keys.

## Ansible conventions

- Variables are prefixed with the role name. Private or derived vars start with `_` and live in `vars/main.yaml`.
- Every default lives in `defaults/main.yaml`: no `| default(...)` for role variables, no `default:` in
  `meta/argument_specs.yaml`.
- Optional keys of list entries get a `<role>_<thing>_defaults` dict, merged in `vars/main.yaml`:
  `_x_items: "{{ [x_item_defaults] | product(x_items) | map('combine') }}"`.
- Task names are `"<Role title>: <Action>"`. Use FQCNs, `.yaml` and 2-space indent.
- Use `ansible_facts['...']`. OS-dependent values are conditional expressions in `defaults/`.
- Use handlers for restarts. A second run must report `changed=0`.
- Host vars only contain real overrides. Image versions are pinned there, with the
  `# renovate: datasource=docker depName=...` comment directly above.
- Comments only where they add something, such as a list format or a non-obvious why. Never restate the name.

### Container roles

Rootless Podman Quadlet pods. Every service role wraps `giftpilz0.container.quadlet`:

```yaml
- name: "Navidrome: Deploy pod"
  ansible.builtin.include_role:
    name: giftpilz0.container.quadlet
  vars:
    quadlet_role: navidrome
    quadlet_extra_files: "{{ navidrome_extra_files }}"
    quadlet_extra_dirs: "{{ navidrome_extra_dirs }}"
    quadlet_units: "{{ (['navidrome-network.service'] if navidrome_network_enabled else []) + ['navidrome-pod.service'] }}"
```

- `templates/<name>-pod/` mirrors `~/.config/containers/systemd/<name>-pod/`, `files/` is copied as is.
- Removing a role from a host does not remove its pod. Delete its unit directory and volumes by hand.
- Local builds use `include_role: tasks_from: build`, and templates use `AutoUpdate=local` for those images.
- Defaults layout: `## Primary` (image, version, autoupdate, network, ports), `## Service`, `# Environment`,
  `## Advanced` (entrypoint, extra files and dirs).
- Traefik is not part of the service roles: the container playbook runs it last.
- Change the shared `quadlet` role as little as possible.

## OpenTofu conventions

- Files: `versions.tf` (pinned providers, local backend), `providers.tf`, `variables.tf`, topic files, `outputs.tf`,
  data in `*.auto.tfvars`.
- Prefer `for_each` over maps from tfvars.
