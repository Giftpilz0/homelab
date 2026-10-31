resource "proxmox_network_linux_bridge" "uplink" {
  node_name  = var.network.node_name
  name       = var.network.bridge.name
  comment    = var.network.bridge.comment
  ports      = var.network.bridge.ports
  vlan_aware = true

  address = var.network.bridge.address
  gateway = var.network.bridge.gateway
}

resource "proxmox_sdn_zone_vlan" "zone" {
  id     = var.network.zone
  bridge = proxmox_network_linux_bridge.uplink.name
  nodes  = [var.network.node_name]
  ipam   = var.network.ipam
}

# One bridge per VLAN on the node, named after the key.
resource "proxmox_sdn_vnet" "vnets" {
  for_each = var.network.vnets

  id    = each.key
  zone  = proxmox_sdn_zone_vlan.zone.id
  tag   = each.value.tag
  alias = each.value.alias
}

# SDN changes stay pending until applied.
resource "proxmox_sdn_applier" "sdn" {
  depends_on = [proxmox_sdn_zone_vlan.zone, proxmox_sdn_vnet.vnets]

  lifecycle {
    replace_triggered_by = [proxmox_sdn_zone_vlan.zone, proxmox_sdn_vnet.vnets]
  }
}
