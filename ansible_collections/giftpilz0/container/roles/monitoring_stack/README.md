# monitoring_stack

Deploys a complete Grafana-free observability stack via Podman quadlets:

| Service           | Role                                                       | Port                                |
| ----------------- | ---------------------------------------------------------- | ----------------------------------- |
| **GarageHQ**      | S3-compatible object store (metrics & log storage backend) | 3900 (S3), 3901 (RPC), 3903 (admin) |
| **Grafana Mimir** | Metrics backend (Prometheus-compatible, long-term storage) | 9009                                |
| **Grafana Loki**  | Log aggregation backend (TSDB index, S3 chunk storage)     | 3100                                |
| **Perses**        | Dashboarding UI (CNCF sandbox, open dashboard spec)        | 8080                                |

All services run inside a single shared pod (`monitoring-stack-pod`) and communicate over localhost.

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

### 3. Expose via Traefik (optional)

```yaml
monitoring_stack_extra_networks:
  - traefik

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

## Provided Dashboards

The role provisions an **Infrastructure** dashboard in Perses (project `default`) with panels for:

- CPU, Memory, Disk, Network (from Prometheus node_exporter metrics via Mimir)
- Recent Logs (from Loki)

Datasources for both Mimir and Loki are registered as global datasources.

## Component Docs

- **GarageHQ**: https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/
- **Mimir**: https://grafana.com/docs/mimir/latest/configure/configuration-parameters/
- **Loki**: https://grafana.com/docs/loki/latest/configure/
- **Perses**: https://perses.dev/perses/docs/configuration/

## Architecture

```
┌──────────────────────────────────────────────────┐
│                 monitoring-stack-pod              │
│                                                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐ │
│  │  Garage  │  │  Mimir   │  │      Loki        │ │
│  │ S3 store │  │ metrics  │  │      logs        │ │
│  │ :3900    │  │ :9009    │  │ :3100            │ │
│  └──────────┘  └──────────┘  └──────────────────┘ │
│                        │                           │
│  ┌──────────────────────────────────────────────┐ │
│  │                  Perses                      │ │
│  │              dashboards :8080                │ │
│  │  datasources: Mimir (:9009) + Loki (:3100)   │ │
│  └──────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────┘
```

## Variables

See [`defaults/main.yaml`](./defaults/main.yaml) for the full variable reference.
