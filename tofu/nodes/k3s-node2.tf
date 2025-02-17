resource "proxmox_vm_qemu" "k3s-node2" {
  name                   = "k3s-node2"
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
          size     = 40
          storage  = "local-lvm"
        }
      }
    }
  }

  network {
    bridge   = "k8s"
    model    = "virtio"
    firewall = true
  }

  # Cloud Init
  cloudinit_cdrom_storage = "local-lvm"
  ipconfig0               = "ip=192.168.65.232/24,gw=192.168.65.1"
  nameserver              = "192.168.65.1"
  ciuser                  = "serveradmin"
  sshkeys                 = var.publick_ssh_key
}
