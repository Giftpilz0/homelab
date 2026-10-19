# Proxmox VM Deployment with OpenTofu

This project uses OpenTofu to automate the deployment of a set of Proxmox virtual machines and Proxmox configuration.
For the state workflow see [../README.md](../README.md).

## Initial import

Import existing VMs and bridges into a fresh state:

```bash
sops exec-env secrets.sops.yaml '
curl -s -k -H "Authorization: PVEAPIToken=$proxmox_api_token" \
  "${proxmox_config_endpoint}api2/json/cluster/resources?type=vm" | jq -r "
.data[] | \"tofu import '\''proxmox_virtual_environment_vm.vms[\\\"\(.name)\\\"]'\'' \(.node)/\(.vmid)\"" | bash
'

tofu import proxmox_network_linux_bridge.uplink pve:vmbr0
tofu plan
```

## Network

`vmbr0` is a VLAN-aware bridge on the `eno1` trunk. The node only has its management address
(untagged). Every key in `network.vnets` becomes an SDN VNet with that VLAN tag. VMs attach to
it with `network_devices = [{ bridge = "<key>" }]`.
