resource "proxmox_vm_qemu" "container" {
  name                   = "container"
  target_node            = "pve"
  memory                 = 4096
  cores                  = 4
  agent                  = 1
  force_create           = false
  tablet                 = false
  onboot                 = true
  define_connection_info = true
  kvm                    = true
  bios                   = "ovmf"
  cpu                    = "host"
  machine                = "q35"
  os_type                = "cloud-init"
  scsihw                 = "virtio-scsi-single"
  hotplug                = "disk,network,usb"
  boot                   = "order=scsi0;net0"
  clone                  = "packer-almalinux"

  disks {
    scsi {
      scsi0 {
        disk {
          cache    = "none"
          iothread = true
          size     = 500
          storage  = "local-lvm"
        }
      }
    }
  }

  network {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = true
  }

  # Cloud Init
  cloudinit_cdrom_storage = "local-lvm"
  ipconfig0               = "ip=192.168.178.221/24,gw=192.168.178.1"
  nameserver              = "192.168.178.1"
  ciuser                  = "serveradmin"
  sshkeys                 = var.publick_ssh_key
}
