variable "keycloak_url" {
  description = "Keycloak server URL"
  type        = string
  default     = "https://login.nixpi.de"
}

variable "keycloak_client_id" {
  description = "Keycloak client ID for OpenTofu"
  type        = string
  default     = "opentofu"
}

variable "realm_name" {
  description = "Name of the Keycloak realm"
  type        = string
  default     = "nixpi"
}

variable "realm_display_name" {
  description = "Display name of the realm"
  type        = string
  default     = "Nixpi"
}

variable "clients" {
  description = "OpenID clients keyed by client ID"
  type = map(object({
    name        = string
    description = string
    access_type = optional(string, "CONFIDENTIAL")
    # Key in secrets.sops.yaml holding the client secret (confidential clients).
    secret_key = optional(string)
    pkce       = optional(bool, false)

    valid_redirect_uris             = list(string)
    valid_post_logout_redirect_uris = optional(list(string))
    web_origins                     = optional(list(string))
    default_scopes                  = list(string)

    # Bind the "browser 1fa" flow instead of the realm default.
    browser_1fa = optional(bool, false)
    # Only these usernames may log in. Empty allows every realm user.
    allowed_users = optional(list(string), [])
  }))

  validation {
    condition     = alltrue([for c in values(var.clients) : c.access_type != "CONFIDENTIAL" || c.secret_key != null])
    error_message = "Confidential clients need a secret_key."
  }
}
