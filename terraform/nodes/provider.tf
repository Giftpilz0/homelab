terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "= 3.0.1-rc1"
    }
  }
}

variable "proxmox_url" {
  type    = string
  default = "https://pve:8006/api2/json"
}

variable "proxmox_user" {
  type    = string
  default = "root@pam"
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "publick_ssh_key" {
  type      = string
  sensitive = true
}

provider "proxmox" {
  pm_api_url      = var.proxmox_url
  pm_password     = var.proxmox_password
  pm_user         = var.proxmox_user
  pm_tls_insecure = true
}
