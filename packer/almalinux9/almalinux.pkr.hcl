packer {
  required_plugins {
    name = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.2"
    }
  }
}

variable "proxmox_url" {
  type    = string
  default = "https://192.168.50.10:8006/api2/json"
}

variable "proxmox_user" {
  type    = string
  default = "root@pam"
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "almalinux_iso_url" {
  type    = string
  default = "http://repo.almalinux.org/almalinux/9.5/isos/x86_64/AlmaLinux-9.5-x86_64-boot.iso"
}

variable "almalinux_sha256sum_url" {
  type    = string
  default = "http://repo.almalinux.org/almalinux/9.5/isos/x86_64/CHECKSUM"
}

source "proxmox-iso" "almalinux9" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true
  unmount_iso              = true
  cloud_init               = true
  cloud_init_storage_pool  = "local-lvm"
  template_name            = "packer-almalinux"
  node                     = "pve"
  bios                     = "ovmf"
  cpu_type                 = "host"
  machine                  = "q35"

  boot_command     = ["<wait><wait>e<down><down><end><bs><bs><bs><bs><bs>inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/almalinux.ks<leftCtrlOn>x<leftCtrlOff>"]
  boot_wait        = "3s"
  http_directory   = "http"
  iso_storage_pool = "local"
  iso_checksum     = "file:${var.almalinux_sha256sum_url}"
  iso_url          = "${var.almalinux_iso_url}"
  iso_download_pve = true
  ssh_username     = "root"
  ssh_password     = "packer"

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
  sources = ["source.proxmox-iso.almalinux9"]
  provisioner "shell" {
    inline = ["passwd -d root", "passwd -l root", "rm -f /etc/ssh/ssh_config.d/allow-root-ssh.conf"]
  }
}
