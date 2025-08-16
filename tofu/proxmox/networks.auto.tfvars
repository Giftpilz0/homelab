networks = {
  "vmbr0" = {
    node_name   = "pve"
    bridge_name = "vmbr0"
    vlan_aware  = false
    comment     = "Bridge for VM networks"
    ports       = ["eno1"]

    network = "192.168.50.10/24"
    gateway = "192.168.50.1"

    sdn_vlan_zone = {
      "Nixpi" = {}
    }
  }
}
