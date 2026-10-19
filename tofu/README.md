# OpenTofu

| Project     | Manages                                      |
|-------------|----------------------------------------------|
| `keycloak/` | Realm, auth flows, roles/groups, OIDC clients |
| `proxmox/`  | Uplink bridge, SDN VLAN zone + VNets, VMs    |

Each project reads its credentials from `secrets.sops.yaml` (sops provider) and keeps
its local state encrypted in git as `state.tfstate.enc`.

## Workflow

```bash
tofu/state-utils.sh decrypt [project...]   # state.tfstate.enc -> state.tfstate (default: all projects)
cd tofu/proxmox && tofu init && tofu plan && tofu apply
tofu/state-utils.sh encrypt [project...]   # -> state.tfstate.enc, removes the plain state and backups
tofu/state-utils.sh status                 # what is decrypted, leftover plain files
```

Always encrypt again before committing.

## Keycloak: restricting a client to some users

Set `allowed_users` on the client in `keycloak/keycloak.auto.tfvars`:

```hcl
"suwayomi" = {
  # ...
  allowed_users = ["moritz"]
}
```

This creates the client role `access`, a group `<client id>-access` that grants it
(membership is managed by OpenTofu), and a browser flow
`browser restricted <client id>` bound to the client that denies login to everyone
else, including users who already have an SSO session.
