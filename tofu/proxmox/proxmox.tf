# ======================================================================================================================
# PROXMOX PROVIDER CONFIGURATION
# ======================================================================================================================
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.83.2"
    }
    sops = {
      source  = "nobbs/sops"
      version = "0.3.1"
    }
  }
}

provider "sops" {}

locals {
  secrets = provider::sops::file("sops-secret.yaml")
}

provider "proxmox" {
  endpoint = var.proxmox_config.endpoint
  insecure = var.proxmox_config.insecure
  username = var.proxmox_config.username
  password = var.proxmox_config.password
  ssh {
    agent    = var.proxmox_config.ssh.agent
    username = var.proxmox_config.ssh.username
  }
}

# ======================================================================================================================
# VARIABLES
# ======================================================================================================================
variable "proxmox_config" {
  description = "Proxmox configuration"
  type = object({
    endpoint = string
    insecure = optional(bool, true)
    username = string
    password = string
    ssh = optional(object({
      agent    = optional(bool, true)
      username = string
    }))
  })
  sensitive = true
}

variable "public_ssh_key" {
  description = "Public SSH key for VM access"
  type        = string
}

variable "default_node_name" {
  description = "Default Proxmox node name"
  type        = string
  default     = "pve"
}

variable "default_datastore" {
  description = "Default datastore for VMs"
  type        = string
  default     = "local-lvm"
}

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

# ======================================================================================================================
# LOCALS
# ======================================================================================================================
locals {
  processed_vms = {
    for vm_key, vm_config in var.vms : vm_key => merge(vm_config, {
      cloud_init = vm_config.cloud_init != null ? merge(vm_config.cloud_init, {
        user_account = vm_config.cloud_init.user_account != null ? merge(vm_config.cloud_init.user_account, {
          keys = length(vm_config.cloud_init.user_account.keys) == 0 ? [var.public_ssh_key] : vm_config.cloud_init.user_account.keys
        }) : vm_config.cloud_init.user_account
      }) : vm_config.cloud_init
    })
  }
}

# ======================================================================================================================
# NETWORKS IMPLEMENTATION
# ======================================================================================================================
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

# ======================================================================================================================
# VM IMPLEMENTATION
# ======================================================================================================================
# VM resources
resource "proxmox_virtual_environment_vm" "vms" {
  for_each = local.processed_vms

  name            = each.value.name
  description     = each.value.description
  tags            = each.value.tags
  started         = each.value.started
  on_boot         = each.value.on_boot
  template        = each.value.template
  stop_on_destroy = each.value.stop_on_destroy

  node_name = each.value.node_name
  vm_id     = each.value.vm_id

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

  # Disks configuration
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

  # Agent configuration
  dynamic "agent" {
    for_each = each.value.agent != null ? [each.value.agent] : []
    content {
      enabled = agent.value.enabled
      trim    = agent.value.trim
      type    = agent.value.type
    }
  }
}

# ======================================================================================================================
# OUTPUTS
# ======================================================================================================================
output "networks_created" {
  value = { for k, v in proxmox_virtual_environment_network_linux_bridge.bridges : k => v.name }
}

output "vlan_zones_created" {
  value = { for k, v in proxmox_virtual_environment_sdn_zone_vlan.vlan_zones : k => v.id }
}

output "vms_created" {
  value = { for k, v in proxmox_virtual_environment_vm.vms : k => v.name }
}
