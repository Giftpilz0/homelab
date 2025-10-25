# Proxmox VM Deployment with OpenTofu

This project uses OpenTofu to automate the deployment of a set of Proxmox virtual machines and Proxmox configuration.

## Getting Started

Import state

```bash
sops exec-env sops-secret.yaml '
curl -s -k -H "Authorization: PVEAPIToken=$proxmox_api_token" \
  "${proxmox_config_endpoint}api2/json/cluster/resources?type=vm" | jq -r "
.data[] | \"tofu import '\''proxmox_virtual_environment_vm.vms[\\\"\(.name)\\\"]'\'' \(.node)/\(.vmid)\"" | bash
'

sops exec-env sops-secret.yaml '
export node_name=pve
curl -s -k -H "Authorization: PVEAPIToken=$proxmox_api_token" \
  "${proxmox_config_endpoint}api2/json/nodes/${node_name}/network?type=bridge" | jq -r "
.data[] | select(.type == \"bridge\") | \"tofu import '\''proxmox_virtual_environment_network_linux_bridge.bridges[\\\"\(.iface)\\\"]'\'' ${node_name}:\(.iface)\"" | bash
'

tofu init
tofu plan
tofu apply
```
