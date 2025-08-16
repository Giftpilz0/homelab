variable "vms" {
  description = "Map of VM configurations"
  type = map(object({
    node_name       = string
    vm_id           = number
    name            = string
    description     = optional(string)
    tags            = optional(list(string))
    started         = optional(bool, true)
    on_boot         = optional(bool, false)
    template        = optional(bool, false)
    stop_on_destroy = optional(bool, false)

    # Clone configuration
    clone = optional(object({
      vm_id     = number
      node_name = string
      full      = optional(bool, true)
    }))

    # Agent configuration
    agent = optional(object({
      enabled = optional(bool, true)
      trim    = optional(bool, false)
      type    = optional(string, "virtio")
    }))

    # CPU configuration
    cpu = object({
      cores   = number
      sockets = optional(number, 1)
      type    = optional(string, "host")
    })

    # Memory configuration
    memory = object({
      dedicated = number
      floating  = optional(number)
    })

    # Operating system
    operating_system = optional(object({
      type = optional(string, "l26")
    }))

    # Disks configuration
    disks = list(object({
      datastore_id = string
      file_format  = optional(string, "qcow2")
      interface    = optional(string, "virtio0")
      iothread     = optional(bool, true)
      discard      = optional(string, "on")
      size         = number
      file_id      = optional(string)
    }))

    # Network devices
    network_devices = list(object({
      bridge      = string
      vlan_id     = optional(number)
      mac_address = optional(string)
      model       = optional(string, "virtio")
      firewall    = optional(bool, false)
      rate_limit  = optional(number)
    }))

    # Cloud-init configuration
    cloud_init = optional(object({
      datastore_id      = string
      user_data_file_id = optional(string)

      user_account = optional(object({
        username = string
        password = optional(string)
        keys     = optional(list(string))
      }))

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

    # Serial devices
    serial_devices = optional(list(object({
      device = string
    })), [])
  }))
}
