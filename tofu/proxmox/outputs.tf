output "vnets" {
  description = "VLAN tag by VNet"
  value       = { for k, v in proxmox_sdn_vnet.vnets : k => v.tag }
}

output "vms_created" {
  description = "VM names by key"
  value       = { for k, v in proxmox_virtual_environment_vm.vms : k => v.name }
}
