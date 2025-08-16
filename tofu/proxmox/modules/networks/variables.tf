variable "networks" {
  description = "Map of network bridges and their SDN VLAN zones"
  type = map(object({
    node_name   = string
    bridge_name = string
    vlan_aware  = bool
    comment     = string
    ports       = list(string)
    network     = optional(string)
    gateway     = optional(string)
    sdn_vlan_zone = map(object({
      mtu         = optional(number, 1500)
      dns         = optional(string)
      dns_zone    = optional(string)
      ipam        = optional(string)
      reverse_dns = optional(string)
    }))
  }))
}
