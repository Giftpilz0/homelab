provider "sops" {}

locals {
  secrets = provider::sops::file("secrets.sops.yaml").data
}

provider "keycloak" {
  client_id     = var.keycloak_client_id
  client_secret = local.secrets.keycloak_client_secret
  url           = var.keycloak_url
}
