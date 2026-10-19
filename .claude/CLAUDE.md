# Homelab

Infrastructure as code for a homelab: Ansible collections + playbooks, OpenTofu, Packer.

```
ansible_collections/giftpilz0/{container,general,server,misc,kubernetes}   roles
ansible-playbook/   run.sh wrapper, inventories/<name>/{playbook.yaml,hosts,group_vars,host_vars}
tofu/{keycloak,proxmox}   OpenTofu projects, tofu/state-utils.sh
packer/almalinux10        VM template
scripts/clean-history.sh  linearize main without bot/merge commits (user runs it, then force-pushes)
```

## Secrets — hard rules

- Never read, print, copy or decrypt: `*.sops.yaml`, `*secrets*`, `*.tfstate*`, `state.tfstate.enc`,
  `.terraform/`, `*.key`, `.env`.
- Never run `sops`, `tofu/state-utils.sh`, `tofu show|output|state|console|apply|import`, or `ansible-inventory`
  (it prints decrypted vars). A hook enforces most of this.
- No recursive reads (`grep -r`, `rg`, `find -exec`, `cp -r`, ...) that reach `tofu/`, e.g. from the repo root:
  decrypted state lies there. Use `git grep` (tracked files only) or name the files.
- If such a command is needed, ask the user to run it with `! <command>`.
- New secrets go into a `*.sops.yaml` file; only reference them by variable name.

## Commands

```bash
cd ansible-playbook
uv sync                                   # python 3.14 + pinned ansible-core, other deps unpinned (uv.lock)
./run.sh [--skip-collections] <inventory> [ansible-playbook args]
uv run ansible-playbook --syntax-check -i localhost, inventories/<inv>/playbook.yaml
cd .. && ANSIBLE_CONFIG=ansible-playbook/ansible.cfg uv run --project ansible-playbook ansible-lint   # must pass

tofu fmt -recursive tofu/
```

`tofu validate`/`plan` call the sops provider and need the user's key — ask the user to run them.

## Ansible conventions

- Variables are prefixed with the role name (`navidrome_*`). Private/derived vars start with `_` and live in
  `vars/main.yaml`.
- **Every default lives in `defaults/main.yaml`.** No `| default(...)` in tasks/templates for role
  variables, no `default:` in `meta/argument_specs.yaml` (argspecs only document type/choices/description).
- Optional keys of list/dict entries get a `<role>_<thing>_defaults` dict in `defaults/` and are merged in
  `vars/main.yaml`:
  `_x_items: "{{ [x_item_defaults] | product(x_items) | map('combine') }}"`.
- Task names: `"<Role title>: <Action>"`. Use FQCNs, `.yaml` extension, 2-space indent.
- Facts via `ansible_facts['...']`, never injected `ansible_*` facts. OS-dependent values are conditional
  expressions in `defaults/`, not `vars/<os>.yaml` (those would override the inventory).
- Comments: short and only where they add something (format of a list, a non-obvious why). No boilerplate
  (`# tasks file for x`), no restating the variable name. Examples only for structured vars.
- Handlers for restarts/reloads; never tasks that report changed on every run (second run must be changed=0).
- Inventory host_vars only contain real overrides; image versions stay pinned there with their
  `# renovate: datasource=docker depName=...` comment directly above the version line.
- Collection versions are pinned in `ansible-playbook/requirements.yaml`; python deps in `pyproject.toml`.

### Container roles (`giftpilz0.container.*`)

Rootless Podman Quadlet pods. Every service role is a thin wrapper around the shared
`giftpilz0.container.quadlet` role:

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

- `templates/<name>-pod/` mirrors `~/.config/containers/systemd/<name>-pod/` (`*.pod`, `*.container`,
  `*.network`, config files). `files/` is copied as is. Stale unit files are removed, pods restart
  only when something changed.
- Local image builds: `include_role: tasks_from: build` with `quadlet_builds` (git repo or role `build/` dir),
  templates use `AutoUpdate=local` for those images.
- Defaults layout: `## Primary` (podman_user, `# Image` → `<role>_image`, renovate comment, `<role>_version`,
  `<role>_autoupdate`, `# Network`, port publishing), `## Service`, `# Environment`, `## Advanced`
  (entrypoint, extra files/dirs).
- Templates use `Image={{ x_image }}:{{ x_version }}`, `quadlet_extra_volumes`, `quadlet_proxy_env`.
- Proxy and `podman_unprivileged_port_start` are host-wide `podman_*` vars (quadlet role defaults).
- Traefik is not included by service roles; the container playbook runs it last on hosts with
  `traefik_http_services`/`traefik_tcp_services`.

## OpenTofu conventions

- Files: `versions.tf` (pinned providers, local backend `state.tfstate`), `providers.tf`
  (`local.secrets = provider::sops::file("secrets.sops.yaml").data`), `variables.tf`, topic files,
  `outputs.tf`, data in `*.auto.tfvars`.
- Prefer `for_each` over maps from tfvars; when renaming resources add `moved` blocks so nothing is recreated.
- Keycloak clients live in `keycloak.auto.tfvars`; `allowed_users` restricts a client to listed users.
