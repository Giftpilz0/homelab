packer {
  required_plugins {
    name = {
      source  = "github.com/hashicorp/proxmox"
      version = "1.2.3"
    }
  }
}

variable "proxmox_config_username" {
  type    = string
  default = env("proxmox_config_username")
}

variable "proxmox_config_password" {
  type    = string
  default = env("proxmox_config_password")
}

variable "proxmox_config_endpoint" {
  type    = string
  default = env("proxmox_config_endpoint")
}

variable "almalinux_iso_url" {
  type    = string
  default = "https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10.0-x86_64-boot.iso"
}

variable "almalinux_sha256sum_url" {
  type    = string
  default = "https://repo.almalinux.org/almalinux/10.0/isos/x86_64/CHECKSUM"
}

source "proxmox-iso" "almalinux10" {
  proxmox_url              = var.proxmox_config_endpoint
  username                 = var.proxmox_config_username
  password                 = var.proxmox_config_password
  insecure_skip_tls_verify = true
  cloud_init               = true
  cloud_init_storage_pool  = "local-lvm"
  template_name            = "packer-almalinux"
  node                     = "pve"
  bios                     = "ovmf"
  cpu_type                 = "host"
  machine                  = "q35"

  boot_command   = ["<wait><wait>e<down><down><end><bs><bs><bs><bs><bs>inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/almalinux.ks<leftCtrlOn>x<leftCtrlOff>"]
  boot_wait      = "30s"
  http_directory = "http"
  ssh_username   = "root"
  ssh_password   = "packer"

  boot_iso {
    iso_storage_pool = "local"
    iso_checksum     = "file:${var.almalinux_sha256sum_url}"
    iso_url          = "${var.almalinux_iso_url}"
    iso_download_pve = true
    unmount          = true
  }

  efi_config {
    pre_enrolled_keys = true
    efi_storage_pool  = "local-lvm"
    efi_format        = "raw"
    efi_type          = "4m"
  }

  scsi_controller = "virtio-scsi-single"
  disks {
    disk_size    = "10G"
    storage_pool = "local-lvm"
    type         = "scsi"
    format       = "raw"
  }

  cores  = "2"
  memory = "2048"

  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = "true"
  }
}

build {
  sources = ["source.proxmox-iso.almalinux10"]
  provisioner "shell" {
    inline = ["passwd -d root", "passwd -l root", "rm -f /etc/ssh/ssh_config.d/allow-root-ssh.conf"]
  }
}
