# monitoring_stack

Deploys a complete Grafana-free observability stack via Podman quadlets:

| Service           | Role                                                       | Port                                |
| ----------------- | ---------------------------------------------------------- | ----------------------------------- |
| **GarageHQ**      | S3-compatible object store (metrics & log storage backend) | 3900 (S3), 3901 (RPC), 3903 (admin) |
| **Grafana Mimir** | Metrics backend (Prometheus-compatible, long-term storage) | 9009                                |
| **Grafana Loki**  | Log aggregation backend (TSDB index, S3 chunk storage)     | 3100                                |
| **Perses**        | Dashboarding UI (CNCF sandbox, open dashboard spec)        | 8080                                |

All services run inside a single shared pod (`monitoring-stack-pod`) and communicate
over localhost. The pod has no host-published ports. Traefik is the only ingress:
Perses authenticates users against Keycloak, while Loki and Mimir expose only their
respective authenticated write paths to Alloy.

## Quickstart

### 1. Initial host vars (first deployment)

```yaml
monitoring_stack_garage_region: "garage"
monitoring_stack_garage_rpc_secret: "<openssl rand -hex 32>"
monitoring_stack_garage_admin_token: "<openssl rand -base64 32>"
monitoring_stack_garage_metrics_token: "<openssl rand -base64 32>"
monitoring_stack_garage_init: true

# Leave empty — garage init will create these and print them
monitoring_stack_mimir_access_key_id: ""
monitoring_stack_mimir_secret_access_key: ""
monitoring_stack_loki_access_key_id: ""
monitoring_stack_loki_secret_access_key: ""
```

### 2. First run

```bash
ansible-playbook ... -e monitoring_stack_garage_init=true
```

### 3. After first run

The playbook output shows the Mimir and Loki access keys. Copy them into your SOPS file and set `monitoring_stack_garage_init: false`:

```yaml
# In your SOPS-encrypted file:
monitoring_stack_mimir_access_key_id: "GK..."
monitoring_stack_mimir_secret_access_key: "..."
monitoring_stack_loki_access_key_id: "GK..."
monitoring_stack_loki_secret_access_key: "..."
```

### 4. Subsequent runs

```yaml
monitoring_stack_garage_init: false
```

### Access control

The stack expects these SOPS-encrypted inventory variables:

- `monitoring_alloy_loki_basic_auth_password`
- `monitoring_alloy_mimir_basic_auth_password`
- `monitoring_stack_loki_basic_auth_hash`
- `monitoring_stack_mimir_basic_auth_hash`
- `monitoring_stack_perses_oidc_client_secret`

Provision the matching confidential `perses` OIDC client through
`tofu/keycloak`. Its callback is
`https://monitoring.nixpi.de/api/auth/providers/oidc/keycloak/callback`.

### Expose via Traefik

```yaml
traefik_networks:
  - monitoring_stack

traefik_http_services:
  - name: perses
    domain: dashboards.example.com
    rule: "Host(`dashboards.example.com`)"
    servers:
      - url: "http://monitoring-stack-pod:8080"
    tls_enabled: true
    acme_enabled: true
```

## Perses provisioning

Perses provisioning is intentionally owned by inventory rather than by this role.
Use `monitoring_stack_extra_dirs` to copy an inventory directory into the
quadlet directory and mount it at `/etc/perses/provisioning`:

```yaml
monitoring_stack_extra_dirs:
  - src: "{{ inventory_dir | dirname }}/host_vars/{{ inventory_hostname }}/assets/perses/provisioning"
    dest: "config/provisioning"
    mount: "/etc/perses/provisioning"
```

The container inventory includes a logs-first example with Loki and Mimir global
datasources. The role does not impose dashboard layout or metric panels.

## Component Docs

- **GarageHQ**: https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/
- **Mimir**: https://grafana.com/docs/mimir/latest/configure/configuration-parameters/
- **Loki**: https://grafana.com/docs/loki/latest/configure/
- **Perses**: https://perses.dev/perses/docs/configuration/

## Architecture

```
┌───────────────────────────────────────────────────┐
│                 monitoring-stack-pod              │
│                                                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐ │
│  │  Garage  │  │  Mimir   │  │      Loki        │ │
│  │ S3 store │  │ metrics  │  │      logs        │ │
│  │ :3900    │  │ :9009    │  │ :3100            │ │
│  └──────────┘  └──────────┘  └──────────────────┘ │
│                        │                          │
│  ┌──────────────────────────────────────────────┐ │
│  │                  Perses                      │ │
│  │              dashboards :8080                │ │
│  │  datasources: Mimir (:9009) + Loki (:3100)   │ │
│  └──────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────┘
```

## Variables

See [`defaults/main.yaml`](./defaults/main.yaml) for the full variable reference.
