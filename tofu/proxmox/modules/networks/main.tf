locals {
  flattened_sdn_zones = merge([
    for bridge_key, bridge_config in var.networks : {
      for zone_key, zone_config in bridge_config.sdn_vlan_zone : "${bridge_key}/${zone_key}" => {
        bridge_key  = bridge_key
        zone_key    = zone_key
        node_name   = bridge_config.node_name
        bridge_name = bridge_config.bridge_name
        mtu         = lookup(zone_config, "mtu", 1500)
        dns         = lookup(zone_config, "dns", null)
        dns_zone    = lookup(zone_config, "dns_zone", null)
        ipam        = lookup(zone_config, "ipam", null)
        reverse_dns = lookup(zone_config, "reverse_dns", null)
      }
    }
  ]...)
}

# Create Linux bridges
resource "proxmox_virtual_environment_network_linux_bridge" "bridges" {
  for_each = var.networks

  node_name  = each.value.node_name
  name       = each.value.bridge_name
  vlan_aware = each.value.vlan_aware
  comment    = each.value.comment
  ports      = each.value.ports

  address = each.value.network
  gateway = each.value.gateway
}

# Create SDN VLAN zones
resource "proxmox_virtual_environment_sdn_zone_vlan" "vlan_zones" {
  for_each = local.flattened_sdn_zones

  id     = each.value.zone_key
  nodes  = [each.value.node_name]
  bridge = proxmox_virtual_environment_network_linux_bridge.bridges[each.value.bridge_key].name

  mtu         = each.value.mtu
  dns         = each.value.dns
  dns_zone    = each.value.dns_zone
  ipam        = each.value.ipam
  reverse_dns = each.value.reverse_dns

  depends_on = [proxmox_virtual_environment_network_linux_bridge.bridges]
}
