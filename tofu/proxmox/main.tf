# Process VMs to inject SSH key
locals {
  publick_ssh_key = var.publick_ssh_key
  processed_vms = {
    for vm_key, vm_config in var.vms : vm_key => merge(vm_config, {
      cloud_init = vm_config.cloud_init != null ? merge(vm_config.cloud_init, {
        user_account = vm_config.cloud_init.user_account != null ? merge(vm_config.cloud_init.user_account, {
          keys = length(vm_config.cloud_init.user_account.keys) == 0 ? [var.publick_ssh_key] : vm_config.cloud_init.user_account.keys
        }) : vm_config.cloud_init.user_account
      }) : vm_config.cloud_init
    })
  }
}


module "networks" {
  source = "./modules/networks"
  networks = var.networks
}

module "vms" {
  source = "./modules/vms"
  vms             = local.processed_vms
  depends_on = [module.networks]
}
