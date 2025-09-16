# Proxmox Configuration
proxmox_config = {
  insecure = true
  endpoint = local.secrets.data.proxmox_config_endpoint
  username = local.secrets.data.proxmox_config_username
  password = local.secrets.data.proxmox_config_password
  ssh = {
    agent    = true
    username = "root"
  }
}

# Shared Configuration
default_node_name = "pve"
default_datastore = "local-lvm"
public_ssh_key    = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB..."

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
      "Nixpi" = {}
    }
  }
}

# VMs Configuration
vms = {
  "lb2" = {
    node_name       = "pve"
    vm_id           = 1002
    name            = "lb2"
    description     = "Load Balancer 2"
    tags            = ["load-balancer", "production"]
    started         = true
    on_boot         = true
    template        = false
    stop_on_destroy = false

    clone = {
      vm_id     = 102
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
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 10
      }
    ]

    network_devices = [
      {
        bridge   = "lb"
        model    = "virtio"
        firewall = false
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
            address = "192.168.70.102/24"
            gateway = "192.168.70.1"
          }
        }
      ]

      dns = {
        servers = ["192.168.70.1"]
      }
    }

    serial_devices = []
  }

  "lb1" = {
    node_name       = "pve"
    vm_id           = 1001
    name            = "lb2"
    description     = "Load Balancer 1"
    tags            = ["load-balancer", "production"]
    started         = true
    on_boot         = true
    template        = false
    stop_on_destroy = false

    clone = {
      vm_id     = 102
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
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 10
      }
    ]

    network_devices = [
      {
        bridge   = "lb"
        model    = "virtio"
        firewall = false
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
            address = "192.168.70.101/24"
            gateway = "192.168.70.1"
          }
        }
      ]

      dns = {
        servers = ["192.168.70.1"]
      }
    }

    serial_devices = []
  }

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

    clone = {
      vm_id     = 102
      node_name = "pve"
      full      = true
    }

    agent = {
      enabled = true
      trim    = false
      type    = "virtio"
    }

    cpu = {
      cores   = 8
      sockets = 1
      type    = "host"
    }

    memory = {
      dedicated = 16384
    }

    operating_system = {
      type = "l26"
    }

    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 500
      }
    ]

    network_devices = [
      {
        bridge   = "k8s"
        model    = "virtio"
        firewall = false
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
            address = "192.168.65.231/24"
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

  "container" = {
    node_name       = "pve"
    vm_id           = 3001
    name            = "container"
    description     = "Container Server"
    tags            = ["container", "docker", "production"]
    started         = true
    on_boot         = true
    template        = false
    stop_on_destroy = false

    clone = {
      vm_id     = 102
      node_name = "pve"
      full      = true
    }

    agent = {
      enabled = true
      trim    = false
      type    = "virtio"
    }

    cpu = {
      cores   = 8
      sockets = 1
      type    = "host"
    }

    memory = {
      dedicated = 8192
    }

    operating_system = {
      type = "l26"
    }

    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 500
      }
    ]

    network_devices = [
      {
        bridge   = "misc"
        model    = "virtio"
        firewall = false
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
            address = "192.168.60.221/24"
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
