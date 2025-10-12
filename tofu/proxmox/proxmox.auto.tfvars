# Proxmox Configuration
proxmox_config = {
  insecure = true
  ssh = {
    agent    = true
    username = "root"
  }
}

# Shared Configuration
default_node_name = "pve"
default_datastore = "local-lvm"
public_ssh_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOAhl7NUVzPjYfk/rB+dS0i6wDPkB5EtlZSfVwGdrWsg"

# Networks Configuration
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
      "sdn" = {}
    }
  }
}

# VMs Configuration
vms = {
  "k3s-node1" = {
    node_name       = "pve"
    vm_id           = 2001
    name            = "k3s-node1"
    description     = "Kubernetes Node 1"
    tags            = ["kubernetes", "k3s", "production"]
    started         = true
    on_boot         = true
    template        = false
    stop_on_destroy = false
    machine         = "q35"
    bios            = "ovmf"
    scsi_hardware   = "virtio-scsi-single"

    clone = {
      vm_id     = 101
      node_name = "pve"
      full      = true
    }

    agent = {
      enabled = true
      trim    = false
      type    = "virtio"
    }

    cpu = {
      cores   = 4
      sockets = 1
      type    = "host"
    }

    memory = {
      dedicated = 6144
    }

    operating_system = {
      type = "l26"
    }

    disks = [
      {
        datastore_id = "local-lvm"
        file_format  = "raw"
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 50
      }
    ]

    network_devices = [
      {
        bridge   = "k8s"
        model    = "virtio"
        firewall = true
      }
    ]

    cloud_init = {
      datastore_id = "local-lvm"

      user_account = {
        username = "serveradmin"
        keys     = []
      }

      ip_configs = [
        {
          ipv4 = {
            address = "192.168.65.10/24"
            gateway = "192.168.65.1"
          }
        }
      ]

      dns = {
        servers = ["192.168.65.1"]
      }
    }

    serial_devices = []
  }

  "k3s-node2" = {
    node_name       = "pve"
    vm_id           = 2002
    name            = "k3s-node2"
    description     = "Kubernetes Node 2"
    tags            = ["kubernetes", "k3s", "production"]
    started         = true
    on_boot         = true
    template        = false
    stop_on_destroy = false
    machine         = "q35"
    bios            = "ovmf"
    scsi_hardware   = "virtio-scsi-single"

    clone = {
      vm_id     = 101
      node_name = "pve"
      full      = true
    }

    agent = {
      enabled = true
      trim    = false
      type    = "virtio"
    }

    cpu = {
      cores   = 4
      sockets = 1
      type    = "host"
    }

    memory = {
      dedicated = 6144
    }

    operating_system = {
      type = "l26"
    }

    disks = [
      {
        datastore_id = "local-lvm"
        file_format  = "raw"
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 50
      }
    ]

    network_devices = [
      {
        bridge   = "k8s"
        model    = "virtio"
        firewall = true
      }
    ]

    cloud_init = {
      datastore_id = "local-lvm"

      user_account = {
        username = "serveradmin"
        keys     = []
      }

      ip_configs = [
        {
          ipv4 = {
            address = "192.168.65.11/24"
            gateway = "192.168.65.1"
          }
        }
      ]

      dns = {
        servers = ["192.168.65.1"]
      }
    }

    serial_devices = []
  }

  "k3s-node3" = {
    node_name       = "pve"
    vm_id           = 2003
    name            = "k3s-node3"
    description     = "Kubernetes Node 3"
    tags            = ["kubernetes", "k3s", "production"]
    started         = true
    on_boot         = true
    template        = false
    stop_on_destroy = false
    machine         = "q35"
    bios            = "ovmf"
    scsi_hardware   = "virtio-scsi-single"

    clone = {
      vm_id     = 101
      node_name = "pve"
      full      = true
    }

    agent = {
      enabled = true
      trim    = false
      type    = "virtio"
    }

    cpu = {
      cores   = 4
      sockets = 1
      type    = "host"
    }

    memory = {
      dedicated = 6144
    }

    operating_system = {
      type = "l26"
    }

    disks = [
      {
        datastore_id = "local-lvm"
        file_format  = "raw"
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 50
      }
    ]

    network_devices = [
      {
        bridge   = "k8s"
        model    = "virtio"
        firewall = true
      }
    ]

    cloud_init = {
      datastore_id = "local-lvm"

      user_account = {
        username = "serveradmin"
        keys     = []
      }

      ip_configs = [
        {
          ipv4 = {
            address = "192.168.65.12/24"
            gateway = "192.168.65.1"
          }
        }
      ]

      dns = {
        servers = ["192.168.65.1"]
      }
    }

    serial_devices = []
  }

  "homeassistant" = {
    node_name       = "pve"
    vm_id           = 4000
    name            = "homeassistant"
    description     = "Homeassistant Server"
    tags            = ["container", "docker", "production"]
    started         = true
    on_boot         = true
    template        = false
    stop_on_destroy = false
    machine         = "q35"
    bios            = "ovmf"
    scsi_hardware   = "virtio-scsi-single"

    clone = {
      vm_id     = 101
      node_name = "pve"
      full      = true
    }

    agent = {
      enabled = true
      trim    = false
      type    = "virtio"
    }

    cpu = {
      cores   = 2
      sockets = 1
      type    = "host"
    }

    memory = {
      dedicated = 2024
    }

    operating_system = {
      type = "l26"
    }

    disks = [
      {
        datastore_id = "local-lvm"
        file_format  = "raw"
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 20
      }
    ]

    network_devices = [
      {
        bridge   = "misc"
        model    = "virtio"
        firewall = true
      }
    ]

    cloud_init = {
      datastore_id = "local-lvm"

      user_account = {
        username = "serveradmin"
        keys     = []
      }

      ip_configs = [
        {
          ipv4 = {
            address = "192.168.60.10/24"
            gateway = "192.168.60.1"
          }
        }
      ]

      dns = {
        servers = ["192.168.60.1"]
      }
    }

    serial_devices = []
  }

  "vaultwarden" = {
    node_name       = "pve"
    vm_id           = 4001
    name            = "vaultwarden"
    description     = "Vaultwarden Server"
    tags            = ["container", "docker", "production"]
    started         = true
    on_boot         = true
    template        = false
    stop_on_destroy = false
    machine         = "q35"
    bios            = "ovmf"
    scsi_hardware   = "virtio-scsi-single"

    clone = {
      vm_id     = 101
      node_name = "pve"
      full      = true
    }

    agent = {
      enabled = true
      trim    = false
      type    = "virtio"
    }

    cpu = {
      cores   = 2
      sockets = 1
      type    = "host"
    }

    memory = {
      dedicated = 2048
    }

    operating_system = {
      type = "l26"
    }

    disks = [
      {
        datastore_id = "local-lvm"
        file_format  = "raw"
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 20
      }
    ]

    network_devices = [
      {
        bridge   = "misc"
        model    = "virtio"
        firewall = true
      }
    ]

    cloud_init = {
      datastore_id = "local-lvm"

      user_account = {
        username = "serveradmin"
        keys     = []
      }

      ip_configs = [
        {
          ipv4 = {
            address = "192.168.60.11/24"
            gateway = "192.168.60.1"
          }
        }
      ]

      dns = {
        servers = ["192.168.60.1"]
      }
    }

    serial_devices = []
  }

  "authentik" = {
    node_name       = "pve"
    vm_id           = 4002
    name            = "authentik"
    description     = "Authentik Server"
    tags            = ["container", "docker", "production"]
    started         = true
    on_boot         = true
    template        = false
    stop_on_destroy = false
    machine         = "q35"
    bios            = "ovmf"
    scsi_hardware   = "virtio-scsi-single"

    clone = {
      vm_id     = 101
      node_name = "pve"
      full      = true
    }

    agent = {
      enabled = true
      trim    = false
      type    = "virtio"
    }

    cpu = {
      cores   = 2
      sockets = 1
      type    = "host"
    }

    memory = {
      dedicated = 2048
    }

    operating_system = {
      type = "l26"
    }

    disks = [
      {
        datastore_id = "local-lvm"
        file_format  = "raw"
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 20
      }
    ]

    network_devices = [
      {
        bridge   = "misc"
        model    = "virtio"
        firewall = true
      }
    ]

    cloud_init = {
      datastore_id = "local-lvm"

      user_account = {
        username = "serveradmin"
        keys     = []
      }

      ip_configs = [
        {
          ipv4 = {
            address = "192.168.60.12/24"
            gateway = "192.168.60.1"
          }
        }
      ]

      dns = {
        servers = ["192.168.60.1"]
      }
    }

    serial_devices = []
  }

  "forgejo" = {
    node_name       = "pve"
    vm_id           = 4003
    name            = "forgejo"
    description     = "Forgejo Server"
    tags            = ["container", "docker", "production"]
    started         = true
    on_boot         = true
    template        = false
    stop_on_destroy = false
    machine         = "q35"
    bios            = "ovmf"
    scsi_hardware   = "virtio-scsi-single"

    clone = {
      vm_id     = 101
      node_name = "pve"
      full      = true
    }

    agent = {
      enabled = true
      trim    = false
      type    = "virtio"
    }

    cpu = {
      cores   = 2
      sockets = 1
      type    = "host"
    }

    memory = {
      dedicated = 2048
    }

    operating_system = {
      type = "l26"
    }

    disks = [
      {
        datastore_id = "local-lvm"
        file_format  = "raw"
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 20
      }
    ]

    network_devices = [
      {
        bridge   = "misc"
        model    = "virtio"
        firewall = true
      }
    ]

    cloud_init = {
      datastore_id = "local-lvm"

      user_account = {
        username = "serveradmin"
        keys     = []
      }

      ip_configs = [
        {
          ipv4 = {
            address = "192.168.60.13/24"
            gateway = "192.168.60.1"
          }
        }
      ]

      dns = {
        servers = ["192.168.60.1"]
      }
    }

    serial_devices = []
  }
}
