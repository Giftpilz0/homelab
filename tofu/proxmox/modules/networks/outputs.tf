output "bridges" {
  description = "Created bridge resources"
  value = {
    for k, v in proxmox_virtual_environment_network_linux_bridge.bridges : k => {
      id   = v.id
      name = v.name
      node = v.node_name
    }
  }
}

output "sdn_zones" {
  description = "Created SDN VLAN zone resources"
  value = {
    for k, v in proxmox_virtual_environment_sdn_zone_vlan.vlan_zones : k => {
      id     = v.id
      bridge = v.bridge
      nodes  = v.nodes
    }
  }
}
