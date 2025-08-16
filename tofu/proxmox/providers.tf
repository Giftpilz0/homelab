terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.81.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_config.endpoint
  insecure  = var.proxmox_config.insecure
  username = var.proxmox_config.username
  password = var.proxmox_config.password
  ssh {
    agent    = var.proxmox_config.ssh.agent
    username = var.proxmox_config.ssh.username
  }
}
