proxmox_config = {
  insecure = true
  ssh = {
    agent    = true
    username = "root"
  }
}

public_ssh_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOAhl7NUVzPjYfk/rB+dS0i6wDPkB5EtlZSfVwGdrWsg"

# eno1 is a trunk: management untagged, VM networks tagged
network = {
  node_name = "pve"
  bridge = {
    name    = "vmbr0"
    ports   = ["eno1"]
    address = "192.168.50.10/24"
    gateway = "192.168.50.1"
    comment = "Uplink: management untagged, VM VLANs tagged"
  }
  zone = "sdn"
  ipam = "pve"
  vnets = {
    "dmz"  = { tag = 55, alias = "DMZ (192.168.55.x)" }
    "misc" = { tag = 60, alias = "Server (192.168.60.x)" }
    "k8s"  = { tag = 65, alias = "Kubernetes (192.168.65.x)" }
  }
}

# Defaults (see variables.tf): node pve, q35/OVMF, full clone of VM 100, raw disk on local-lvm,
# cloud-init user serveradmin with public_ssh_key
vms = {
  "k3s-node1" = {
    vm_id       = 2001
    name        = "k3s-node1"
    description = "Kubernetes Node 1"
    tags        = ["kubernetes", "k3s", "production"]
    started     = false
    on_boot     = false

    cpu             = { cores = 4 }
    memory          = { dedicated = 6144 }
    disks           = [{ size = 50 }]
    network_devices = [{ bridge = "k8s" }]

    cloud_init = {
      ip_configs = [{ ipv4 = { address = "192.168.65.10/24", gateway = "192.168.65.1" } }]
      dns        = { servers = ["192.168.65.1"] }
    }
  }

  "homeassistant" = {
    vm_id       = 4000
    name        = "homeassistant"
    description = "Homeassistant Server"
    tags        = ["container", "docker", "production"]

    cpu             = { cores = 2 }
    memory          = { dedicated = 4096 }
    disks           = [{ size = 20 }]
    network_devices = [{ bridge = "misc" }]

    cloud_init = {
      ip_configs = [{ ipv4 = { address = "192.168.60.10/24", gateway = "192.168.60.1" } }]
      dns        = { servers = ["192.168.60.1"] }
    }
  }

  "vaultwarden" = {
    vm_id       = 4001
    name        = "vaultwarden"
    description = "Vaultwarden Server"
    tags        = ["container", "docker", "production"]

    cpu             = { cores = 2 }
    memory          = { dedicated = 2048 }
    disks           = [{ size = 20 }]
    network_devices = [{ bridge = "misc" }]

    cloud_init = {
      ip_configs = [{ ipv4 = { address = "192.168.60.11/24", gateway = "192.168.60.1" } }]
      dns        = { servers = ["192.168.60.1"] }
    }
  }

  "misc" = {
    vm_id       = 4002
    name        = "misc"
    description = "Misc Server"
    tags        = ["container", "docker", "production"]

    cpu             = { cores = 2 }
    memory          = { dedicated = 4096 }
    disks           = [{ size = 20 }]
    network_devices = [{ bridge = "misc" }]

    cloud_init = {
      ip_configs = [{ ipv4 = { address = "192.168.60.12/24", gateway = "192.168.60.1" } }]
      dns        = { servers = ["192.168.60.1"] }
    }
  }

  "forgejo" = {
    vm_id       = 4003
    name        = "forgejo"
    description = "Forgejo Server"
    tags        = ["container", "docker", "production"]

    cpu             = { cores = 2 }
    memory          = { dedicated = 4096 }
    disks           = [{ size = 20 }]
    network_devices = [{ bridge = "misc" }]

    cloud_init = {
      ip_configs = [{ ipv4 = { address = "192.168.60.13/24", gateway = "192.168.60.1" } }]
      dns        = { servers = ["192.168.60.1"] }
    }
  }

  "opencloud" = {
    vm_id       = 4004
    name        = "opencloud"
    description = "OpenCloud Server"
    tags        = ["container", "docker", "production"]

    cpu             = { cores = 4 }
    memory          = { dedicated = 8192 }
    disks           = [{ size = 500 }]
    network_devices = [{ bridge = "misc" }]

    cloud_init = {
      ip_configs = [{ ipv4 = { address = "192.168.60.14/24", gateway = "192.168.60.1" } }]
      dns        = { servers = ["192.168.60.1"] }
    }
  }

  "bumper" = {
    vm_id       = 4005
    name        = "bumper"
    description = "Bumper Server"
    tags        = ["container", "docker", "production"]

    cpu             = { cores = 4 }
    memory          = { dedicated = 4096 }
    disks           = [{ size = 20 }]
    network_devices = [{ bridge = "misc" }]

    cloud_init = {
      ip_configs = [{ ipv4 = { address = "192.168.60.15/24", gateway = "192.168.60.1" } }]
      dns        = { servers = ["192.168.60.1"] }
    }
  }

  "keycloak" = {
    vm_id       = 4006
    name        = "keycloak"
    description = "Keycloak Server"
    tags        = ["container", "docker", "production"]

    cpu             = { cores = 2 }
    memory          = { dedicated = 4096 }
    disks           = [{ size = 20 }]
    network_devices = [{ bridge = "misc" }]

    cloud_init = {
      ip_configs = [{ ipv4 = { address = "192.168.60.16/24", gateway = "192.168.60.1" } }]
      dns        = { servers = ["192.168.60.1"] }
    }
  }

  "monitoring" = {
    vm_id       = 4007
    name        = "monitoring"
    description = "Monitoring Server"
    tags        = ["container", "docker", "production"]

    cpu             = { cores = 2 }
    memory          = { dedicated = 4096 }
    disks           = [{ size = 50 }]
    network_devices = [{ bridge = "misc" }]

    cloud_init = {
      ip_configs = [{ ipv4 = { address = "192.168.60.17/24", gateway = "192.168.60.1" } }]
      dns        = { servers = ["192.168.60.1"] }
    }
  }

  "acme" = {
    vm_id       = 4008
    name        = "acme"
    description = "acme Server"
    tags        = ["container", "docker", "production"]

    cpu             = { cores = 1 }
    memory          = { dedicated = 1024 }
    disks           = [{ size = 20 }]
    network_devices = [{ bridge = "dmz" }]

    cloud_init = {
      ip_configs = [{ ipv4 = { address = "192.168.55.10/24", gateway = "192.168.55.1" } }]
      dns        = { servers = ["192.168.55.1"] }
    }
  }
}
