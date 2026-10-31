terraform {
  required_version = ">= 1.8"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "5.10.0"
    }
    sops = {
      source  = "nobbs/sops"
      version = "0.3.3"
    }
  }

  # Kept encrypted in git as state.tfstate.enc, see ../state-utils.sh.
  backend "local" {
    path = "state.tfstate"
  }
}
