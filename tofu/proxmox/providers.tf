provider "sops" {}

locals {
  secrets = provider::sops::file("secrets.sops.yaml").data
}

provider "proxmox" {
  insecure  = var.proxmox_config.insecure
  endpoint  = local.secrets.proxmox_config_endpoint
  api_token = local.secrets.proxmox_api_token

  ssh {
    agent    = var.proxmox_config.ssh.agent
    username = var.proxmox_config.ssh.username
  }
}
