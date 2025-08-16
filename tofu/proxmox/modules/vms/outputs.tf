output "vms" {
  description = "Created VM resources"
  value = {
    for k, v in proxmox_virtual_environment_vm.vms : k => {
      id             = v.id
      vm_id          = v.vm_id
      name           = v.name
      node_name      = v.node_name
      started        = v.started
      ipv4_addresses = v.ipv4_addresses
      ipv6_addresses = v.ipv6_addresses
      mac_addresses  = v.mac_addresses
    }
  }
}

output "vm_ids" {
  description = "Map of VM names to VM IDs"
  value = {
    for k, v in proxmox_virtual_environment_vm.vms : k => v.vm_id
  }
}

output "vm_ips" {
  description = "Map of VM names to their IP addresses"
  value = {
    for k, v in proxmox_virtual_environment_vm.vms : k => v.ipv4_addresses
  }
}
