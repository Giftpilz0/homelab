proxmox_config = {
  endpoint = "https://192.168.50.10:8006/"
  insecure = true
  username = "root@pam"
  password = "changeme"
  ssh = {
    agent    = true
    username = "root"
  }
}
