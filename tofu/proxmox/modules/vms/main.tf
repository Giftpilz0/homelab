resource "proxmox_virtual_environment_vm" "vms" {
  for_each = var.vms

  node_name       = each.value.node_name
  vm_id           = each.value.vm_id
  name            = each.value.name
  description     = each.value.description
  tags            = each.value.tags
  started         = each.value.started
  on_boot         = each.value.on_boot
  template        = each.value.template
  stop_on_destroy = each.value.stop_on_destroy

  # Clone configuration
  dynamic "clone" {
    for_each = each.value.clone != null ? [each.value.clone] : []
    content {
      vm_id     = clone.value.vm_id
      node_name = clone.value.node_name
      full      = clone.value.full
    }
  }

  # Agent configuration
  agent {
    enabled = each.value.agent.enabled
    trim    = each.value.agent.trim
    type    = each.value.agent.type
  }

  # CPU configuration
  cpu {
    cores   = each.value.cpu.cores
    sockets = each.value.cpu.sockets
    type    = each.value.cpu.type
  }

  # Memory configuration
  memory {
    dedicated = each.value.memory.dedicated
    floating  = each.value.memory.floating
  }

  # Operating system
  operating_system {
    type = each.value.operating_system.type
  }

  # Disk configurations
  dynamic "disk" {
    for_each = each.value.disks
    content {
      datastore_id = disk.value.datastore_id
      file_format  = disk.value.file_format
      interface    = disk.value.interface
      iothread     = disk.value.iothread
      discard      = disk.value.discard
      size         = disk.value.size
      file_id      = disk.value.file_id
    }
  }

  # Network devices
  dynamic "network_device" {
    for_each = each.value.network_devices
    content {
      bridge      = network_device.value.bridge
      vlan_id     = network_device.value.vlan_id
      mac_address = network_device.value.mac_address
      model       = network_device.value.model
      firewall    = network_device.value.firewall
      rate_limit  = network_device.value.rate_limit
    }
  }

  # Cloud-init configuration
  dynamic "initialization" {
    for_each = each.value.cloud_init != null ? [each.value.cloud_init] : []
    content {
      datastore_id      = initialization.value.datastore_id
      user_data_file_id = initialization.value.user_data_file_id

      # User account
      dynamic "user_account" {
        for_each = initialization.value.user_account != null ? [initialization.value.user_account] : []
        content {
          username = user_account.value.username
          password = user_account.value.password
          keys     = user_account.value.keys
        }
      }

      # IP configurations
      dynamic "ip_config" {
        for_each = initialization.value.ip_configs
        content {
          dynamic "ipv4" {
            for_each = ip_config.value.ipv4 != null ? [ip_config.value.ipv4] : []
            content {
              address = ipv4.value.address
              gateway = ipv4.value.gateway
            }
          }
          dynamic "ipv6" {
            for_each = ip_config.value.ipv6 != null ? [ip_config.value.ipv6] : []
            content {
              address = ipv6.value.address
              gateway = ipv6.value.gateway
            }
          }
        }
      }

      # DNS configuration
      dynamic "dns" {
        for_each = initialization.value.dns != null ? [initialization.value.dns] : []
        content {
          domain  = dns.value.domain
          servers = dns.value.servers
        }
      }
    }
  }

  # Serial devices
  dynamic "serial_device" {
    for_each = each.value.serial_devices
    content {
      device = serial_device.value.device
    }
  }
}
