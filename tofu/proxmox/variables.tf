variable "proxmox_config" {
  description = "Proxmox connection settings (endpoint and API token come from the sops secrets file)"
  type = object({
    insecure = optional(bool, true)
    ssh = optional(object({
      agent    = optional(bool, true)
      username = optional(string, "root")
    }), {})
  })
  default = {}
}

variable "public_ssh_key" {
  description = "Public SSH key for VM access"
  type        = string
}

variable "network" {
  description = "VLAN-aware uplink bridge of the node and the SDN VNets (one VLAN each) the VMs attach to"
  type = object({
    node_name = string
    bridge = object({
      name    = string
      ports   = list(string)
      address = string
      gateway = string
      comment = optional(string)
    })
    zone = string
    # Fixed once the zone has subnets
    ipam = optional(string)
    vnets = map(object({
      tag   = number
      alias = optional(string)
    }))
  })

  validation {
    condition = alltrue([
      for k, v in var.network.vnets :
      can(regex("^[a-z][a-z0-9]{0,7}$", k)) && (v.alias == null || can(regex("^[A-Za-z0-9 ._()-]+$", v.alias)))
    ])
    error_message = "VNet keys: lowercase alphanumeric, max 8 chars. Aliases: letters, digits, spaces and ._()- only."
  }
}

variable "vms" {
  description = "VMs by key; network_devices[].bridge is a VNet key or the uplink bridge"
  type = map(object({
    node_name       = optional(string, "pve")
    vm_id           = number
    name            = string
    description     = optional(string)
    tags            = optional(list(string))
    started         = optional(bool, true)
    on_boot         = optional(bool, true)
    template        = optional(bool, false)
    stop_on_destroy = optional(bool, false)
    machine         = optional(string, "q35")
    bios            = optional(string, "ovmf")
    scsi_hardware   = optional(string, "virtio-scsi-single")

    # null: no clone
    clone = optional(object({
      vm_id     = optional(number, 100)
      node_name = optional(string, "pve")
      full      = optional(bool, true)
    }), {})

    agent = optional(object({
      enabled = optional(bool, true)
      trim    = optional(bool, false)
      type    = optional(string, "virtio")
    }), {})

    cpu = object({
      cores   = number
      sockets = optional(number, 1)
      type    = optional(string, "host")
    })

    memory = object({
      dedicated = number
      floating  = optional(number)
    })

    operating_system = optional(object({
      type = optional(string, "l26")
    }), {})

    disks = list(object({
      datastore_id = optional(string, "local-lvm")
      file_format  = optional(string, "raw")
      interface    = optional(string, "scsi0")
      iothread     = optional(bool, true)
      discard      = optional(string, "on")
      size         = number
      file_id      = optional(string)
    }))

    network_devices = list(object({
      bridge      = string
      vlan_id     = optional(number)
      mac_address = optional(string)
      model       = optional(string, "virtio")
      firewall    = optional(bool, true)
      rate_limit  = optional(number)
    }))

    cloud_init = optional(object({
      datastore_id      = optional(string, "local-lvm")
      user_data_file_id = optional(string)

      user_account = optional(object({
        username = optional(string, "serveradmin")
        password = optional(string)
        keys     = optional(list(string), []) # empty: use var.public_ssh_key
      }), {})

      ip_configs = optional(list(object({
        ipv4 = optional(object({
          address = string
          gateway = optional(string)
        }))
        ipv6 = optional(object({
          address = string
          gateway = optional(string)
        }))
      })), [])

      dns = optional(object({
        domain  = optional(string)
        servers = optional(list(string))
      }))
    }))

    serial_devices = optional(list(object({
      device = string
    })), [])
  }))
}
