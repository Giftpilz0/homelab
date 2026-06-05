# ======================================================================================================================
# KEYCLOAK PROVIDER CONFIGURATION
# ======================================================================================================================
terraform {
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "5.8.0"
    }
    sops = {
      source  = "nobbs/sops"
      version = "0.3.1"
    }
  }

  backend "local" {
    path = "state.tfstate"
  }
}

provider "sops" {}

locals {
  secrets = provider::sops::file("secrets.yaml")
}

provider "keycloak" {
  client_id     = var.keycloak_client_id
  client_secret = local.secrets.data.keycloak_client_secret
  url           = var.keycloak_url
}

# ======================================================================================================================
# VARIABLES
# ======================================================================================================================
variable "keycloak_url" {
  description = "Keycloak server URL"
  type        = string
  default     = "https://login.nixpi.de"
}

variable "keycloak_client_id" {
  description = "Keycloak client ID for Terraform"
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

#variable "initial_admin_password" {
#  description = "Initial password for the realm admin user"
#  type        = string
#  sensitive   = true
#}

# ======================================================================================================================
# REALM CONFIGURATION
# ======================================================================================================================
resource "keycloak_realm" "nixpi" {
  realm        = var.realm_name
  enabled      = true
  display_name = var.realm_display_name
  display_name_html = "<b>${var.realm_display_name}</b>"
  #login_theme       = "nixpi"
  #account_theme     = "nixpi"

  # Authentication settings
  remember_me              = true
  login_with_email_allowed = true
  duplicate_emails_allowed = false
  registration_allowed     = false
  edit_username_allowed    = false
  reset_password_allowed   = true

  # Security settings
  ssl_required = "external"
  access_code_lifespan = "1h"

  # Internationalization
  internationalization {
    supported_locales = [
      "en",
      "de"
    ]
    default_locale = "de"
  }

  # WebAuthn settings
  web_authn_policy {
    relying_party_entity_name = "Nixpi SSO"
    relying_party_id          = "login.nixpi.de"
    signature_algorithms      = ["ES256", "RS256", "ES512", "RS512"]
  }

  # Security defenses
  security_defenses {
    headers {
      x_frame_options                     = "DENY"
      content_security_policy             = "frame-src 'self'; frame-ancestors 'self'; object-src 'none';"
      content_security_policy_report_only = ""
      x_content_type_options              = "nosniff"
      x_robots_tag                        = "none"
      x_xss_protection                    = "1; mode=block"
      strict_transport_security           = "max-age=31536000; includeSubDomains"
    }

    brute_force_detection {
      permanent_lockout                = false
      max_login_failures               = 30
      wait_increment_seconds           = 60
      quick_login_check_milli_seconds  = 1000
      minimum_quick_login_wait_seconds = 60
      max_failure_wait_seconds         = 900
      failure_reset_time_seconds       = 43200
    }
  }

  # Additional security settings
  sso_session_idle_timeout             = "1800s"    # 30 minutes
  sso_session_max_lifespan             = "36000s"   # 10 hours
  sso_session_idle_timeout_remember_me = "2592000s" # 30 days
  sso_session_max_lifespan_remember_me = "2592000s" # 30 days
}

# resource "keycloak_realm_keystore_aes_generated" "keystore_aes_generated" {
#   name        = "aes-generated"
#   realm_id    = keycloak_realm.nixpi.id
#   enabled     = true
#   active      = true
#   priority    = 100
#   secret_size = 16
# }

# resource "keycloak_realm_keystore_rsa_generated" "keystore_rsa_generated" {
#   name      = "rsa-generated"
#   realm_id  = keycloak_realm.nixpi.id
#   enabled   = true
#   active    = true
#   priority  = 100
#   algorithm = "RS256"
#   key_size  = 4096
# }

# resource "keycloak_realm_keystore_hmac_generated" "keystore_hmac_generated" {
#   name        = "hmac-generated-hs512"
#   realm_id    = keycloak_realm.nixpi.id
#   enabled     = true
#   active      = true
#   priority    = 100
#   algorithm   = "HS512"
#   secret_size = 128
# }

# ======================================================================================================================
# REQUIRED ACTIONS
# ======================================================================================================================
resource "keycloak_required_action" "custom_terms_and_conditions" {
  realm_id = keycloak_realm.nixpi.id
  alias    = "TERMS_AND_CONDITIONS"
  enabled  = false
  name     = "Terms and Conditions"
  priority = 0
}

resource "keycloak_required_action" "configure_otp" {
  realm_id       = keycloak_realm.nixpi.id
  alias          = "CONFIGURE_TOTP"
  default_action = false
  enabled        = true
  name           = "Configure OTP"
  priority       = 10
}

resource "keycloak_required_action" "update_password" {
  realm_id = keycloak_realm.nixpi.id
  alias    = "UPDATE_PASSWORD"
  enabled  = false
  name     = "Update Password"
  priority = 20
}

resource "keycloak_required_action" "update_profile" {
  realm_id = keycloak_realm.nixpi.id
  alias    = "UPDATE_PROFILE"
  enabled  = true
  name     = "Update Profile"
  priority = 30
}

resource "keycloak_required_action" "verify_email" {
  realm_id = keycloak_realm.nixpi.id
  alias    = "VERIFY_EMAIL"
  enabled  = true
  name     = "Verify Email"
  priority = 40
}

resource "keycloak_required_action" "update_user_locale" {
  realm_id = keycloak_realm.nixpi.id
  alias    = "update_user_locale"
  enabled  = true
  name     = "Update User Locale"
  priority = 50
}

resource "keycloak_required_action" "webauthn_register" {
  realm_id = keycloak_realm.nixpi.id
  alias    = "webauthn-register"
  enabled  = true
  name     = "Webauthn Register"
  priority = 60
}

resource "keycloak_required_action" "verify_profile" {
  realm_id = keycloak_realm.nixpi.id
  alias    = "VERIFY_PROFILE"
  enabled  = false
  name     = "Verify Profile"
  priority = 70
}

# ======================================================================================================================
# REALM EVENTS CONFIGURATION
# ======================================================================================================================
resource "keycloak_realm_events" "realm_events" {
  realm_id = keycloak_realm.nixpi.id

  events_enabled    = true
  events_expiration = 7889238 # 3 months

  admin_events_enabled         = true
  admin_events_details_enabled = true

  enabled_event_types = [
  ]

  events_listeners = [
    "jboss-logging"
  ]
}

# ======================================================================================================================
# ROLES — OpenCloud role mapping
# ======================================================================================================================
resource "keycloak_role" "opencloud_admin" {
  realm_id    = keycloak_realm.nixpi.id
  name        = "opencloudAdmin"
  description = "OpenCloud administrator role"
}

resource "keycloak_role" "opencloud_space_admin" {
  realm_id    = keycloak_realm.nixpi.id
  name        = "opencloudSpaceAdmin"
  description = "OpenCloud space administrator role"
}

resource "keycloak_role" "opencloud_user" {
  realm_id    = keycloak_realm.nixpi.id
  name        = "opencloudUser"
  description = "OpenCloud standard user role"
}

resource "keycloak_role" "opencloud_guest" {
  realm_id    = keycloak_realm.nixpi.id
  name        = "opencloudGuest"
  description = "OpenCloud guest role"
}

resource "keycloak_openid_client_scope" "opencloud_realm_roles" {
  realm_id    = keycloak_realm.nixpi.id
  name        = "opencloud-realm-roles"
  description = "Maps realm roles to flat 'roles' claim for OpenCloud"
}

resource "keycloak_openid_user_realm_role_protocol_mapper" "opencloud_realm_roles_mapper" {
  realm_id        = keycloak_realm.nixpi.id
  client_scope_id = keycloak_openid_client_scope.opencloud_realm_roles.id
  name            = "realm-roles"
  claim_name      = "roles"
  multivalued     = true
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# ======================================================================================================================
# GROUPS
# ======================================================================================================================
resource "keycloak_group" "opencloud_admin" {
  realm_id = keycloak_realm.nixpi.id
  name     = "opencloud-admin"
}

resource "keycloak_group" "opencloud_space_admin" {
  realm_id = keycloak_realm.nixpi.id
  name     = "opencloud-space-admin"
}

resource "keycloak_group" "opencloud_user" {
  realm_id = keycloak_realm.nixpi.id
  name     = "opencloud-user"
}

resource "keycloak_group" "opencloud_guest" {
  realm_id = keycloak_realm.nixpi.id
  name     = "opencloud-guest"
}

resource "keycloak_group_roles" "opencloud_admin_roles" {
  realm_id = keycloak_realm.nixpi.id
  group_id = keycloak_group.opencloud_admin.id
  role_ids = [keycloak_role.opencloud_admin.id]
}

resource "keycloak_group_roles" "opencloud_space_admin_roles" {
  realm_id = keycloak_realm.nixpi.id
  group_id = keycloak_group.opencloud_space_admin.id
  role_ids = [keycloak_role.opencloud_space_admin.id]
}

resource "keycloak_group_roles" "opencloud_user_roles" {
  realm_id = keycloak_realm.nixpi.id
  group_id = keycloak_group.opencloud_user.id
  role_ids = [keycloak_role.opencloud_user.id]
}

resource "keycloak_group_roles" "opencloud_guest_roles" {
  realm_id = keycloak_realm.nixpi.id
  group_id = keycloak_group.opencloud_guest.id
  role_ids = [keycloak_role.opencloud_guest.id]
}

resource "keycloak_group" "forgejo_admin" {
  realm_id = keycloak_realm.nixpi.id
  name     = "forgejo-admin"
}

resource "keycloak_openid_client_scope" "forgejo_groups" {
  realm_id    = keycloak_realm.nixpi.id
  name        = "forgejo-groups"
  description = "Maps group memberships (name only, no path prefix) for Forgejo admin group matching"
}

resource "keycloak_openid_group_membership_protocol_mapper" "forgejo_groups_mapper" {
  realm_id        = keycloak_realm.nixpi.id
  client_scope_id = keycloak_openid_client_scope.forgejo_groups.id
  name            = "groups"
  claim_name      = "groups"
  full_path       = false
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# ======================================================================================================================
# USER MANAGEMENT
# ======================================================================================================================
resource "keycloak_default_roles" "default_roles" {
  realm_id = keycloak_realm.nixpi.id
  default_roles = [
    "offline_access",
    "uma_authorization",
    "account/manage-account",
    "account/view-profile",
  ]
}

resource "keycloak_default_groups" "default_groups" {
  realm_id  = keycloak_realm.nixpi.id
  group_ids = [keycloak_group.opencloud_user.id]
}

#resource "keycloak_user" "realm_admin" {
#  realm_id   = keycloak_realm.nixpi.id
#  username   = "realm-admin"
#  email      = var.realm_admin_email
#  first_name = "Realm"
#  last_name  = "Administrator"
#  enabled    = true
#
#  initial_password {
#    value     = var.initial_admin_password
#    temporary = false
#  }
#
#  role_mappings = [
#    keycloak_role.realm_admin.id,
#    keycloak_role.admin.id
#  ]
#
#  group_memberships = [
#    keycloak_group.administrators.id
#  ]
#}

# ======================================================================================================================
# AUTHENTICATION FLOW CONFIGURATION
# ======================================================================================================================
resource "keycloak_authentication_flow" "browser_flow" {
  realm_id    = keycloak_realm.nixpi.id
  alias       = "browser 2fa"
  description = "Browser authentication flow that forces 2FA"
}

resource "keycloak_authentication_execution" "browser_cookie" {
  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_flow.browser_flow.alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

resource "keycloak_authentication_subflow" "password_and_2fa" {
  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_flow.browser_flow.alias
  alias             = "Password and 2FA subflow"
  requirement       = "ALTERNATIVE"
  priority          = 20
}

resource "keycloak_authentication_execution" "browser_username_password_form" {
  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow.password_and_2fa.alias
  authenticator     = "auth-username-password-form"
  requirement       = "REQUIRED"
  priority          = 30
}

resource "keycloak_authentication_subflow" "_2fa_subflow" {
  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow.password_and_2fa.alias
  alias             = "2FA subflow"
  requirement       = "REQUIRED"
  priority          = 40
}

resource "keycloak_authentication_execution" "browser_otp_form" {
  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow._2fa_subflow.alias
  authenticator     = "auth-otp-form"
  requirement       = "ALTERNATIVE"
  priority          = 50
}

resource "keycloak_authentication_execution" "browser_webauthn_form" {
  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow._2fa_subflow.alias
  authenticator     = "webauthn-authenticator"
  requirement       = "ALTERNATIVE"
  priority          = 60
}


resource "keycloak_authentication_subflow" "otp_default" {
  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow._2fa_subflow.alias
  alias             = "OTP Default Subflow"
  requirement       = "ALTERNATIVE"
  priority          = 70
}

resource "keycloak_authentication_execution" "otp_default_form" {
  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow.otp_default.alias
  authenticator     = "auth-otp-form"
  requirement       = "REQUIRED"
  priority          = 80
}

resource "keycloak_authentication_flow" "browser_flow_2" {
  realm_id    = keycloak_realm.nixpi.id
  alias       = "browser 1fa"
  description = "Browser authentication flow"
}

resource "keycloak_authentication_execution" "browser_cookie_2" {
  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_flow.browser_flow_2.alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

resource "keycloak_authentication_subflow" "password" {
  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_flow.browser_flow_2.alias
  alias             = "Password subflow"
  requirement       = "ALTERNATIVE"
  priority          = 20
}

resource "keycloak_authentication_execution" "browser_username_password_form_2" {
  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow.password.alias
  authenticator     = "auth-username-password-form"
  requirement       = "REQUIRED"
  priority          = 30
}

# ======================================================================================================================
# CLIENT CONFIGURATION
# ======================================================================================================================

# ======================================================================================================================
# CLIENT: forgejo
# ======================================================================================================================
resource "keycloak_openid_client" "forgejo" {
  realm_id    = keycloak_realm.nixpi.id
  client_id   = "forgejo"
  name        = "Forgejo"
  description = "Forgejo Git"

  access_type   = "CONFIDENTIAL"
  client_secret = local.secrets.data.forgejo_client_secret

  # Authentication flow
  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false

  # Session settings
  use_refresh_tokens           = true

  valid_redirect_uris = [
    "https://forgejo.nixpi.de/user/oauth2/keycloak/callback"
  ]

  # Valid redirect URIs
  valid_post_logout_redirect_uris = [
    "https://forgejo.nixpi.de"
  ]

  # Web origins for CORS
  web_origins = [
    "https://forgejo.nixpi.de"
  ]

  # Service accounts
  service_accounts_enabled = false

  # Authentication flow
  authentication_flow_binding_overrides {
    browser_id = keycloak_authentication_flow.browser_flow_2.id
  }
}

resource "keycloak_openid_client_default_scopes" "forgejo_default_scopes" {
  realm_id  = keycloak_realm.nixpi.id
  client_id = keycloak_openid_client.forgejo.id

  default_scopes = [
    "profile",
    "email",
    keycloak_openid_client_scope.forgejo_groups.name,
  ]
}

# ======================================================================================================================
# CLIENT: vaultwarden (confidential OIDC client)
# ======================================================================================================================
resource "keycloak_openid_client" "vaultwarden" {
  realm_id    = keycloak_realm.nixpi.id
  client_id   = "vaultwarden"
  name        = "Vaultwarden"
  description = "Vaultwarden password manager"

  access_type   = "CONFIDENTIAL"
  client_secret = local.secrets.data.vaultwarden_client_secret

  # Authentication flow
  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false

  # Session settings
  use_refresh_tokens           = true

  valid_redirect_uris = [
    "https://vaultwarden.nixpi.de/identity/connect/oidc-signin"
  ]

  # Valid redirect URIs
  valid_post_logout_redirect_uris = [
    "https://vaultwarden.nixpi.de"
  ]

  # Web origins for CORS
  web_origins = [
    "https://vaultwarden.nixpi.de"
  ]

  # Service accounts
  service_accounts_enabled = false

  # Authentication flow
  authentication_flow_binding_overrides {
    browser_id = keycloak_authentication_flow.browser_flow_2.id
  }
}

resource "keycloak_openid_client_default_scopes" "vaultwarden_default_scopes" {
  realm_id  = keycloak_realm.nixpi.id
  client_id = keycloak_openid_client.vaultwarden.id

  default_scopes = [
    "profile",
    "email"
  ]
}

# ======================================================================================================================
# CLIENT: OpenCloudWeb (public SPA client)
# ======================================================================================================================
resource "keycloak_openid_client" "opencloud_web" {
  realm_id    = keycloak_realm.nixpi.id
  client_id   = "OpenCloudWeb"
  name        = "OpenCloud Web"
  description = "OpenCloud web application"

  access_type = "PUBLIC"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  use_refresh_tokens           = true
  pkce_code_challenge_method   = "S256"

  valid_redirect_uris = [
    "https://opencloud.nixpi.de/",
    "https://opencloud.nixpi.de/oidc-callback.html",
    "https://opencloud.nixpi.de/oidc-silent-redirect.html"
  ]

  valid_post_logout_redirect_uris = [
    "https://opencloud.nixpi.de",
    "https://opencloud.nixpi.de/*"
  ]

  web_origins = [
    "https://opencloud.nixpi.de"
  ]

  service_accounts_enabled = false
}

resource "keycloak_openid_client_default_scopes" "opencloud_web_default_scopes" {
  realm_id  = keycloak_realm.nixpi.id
  client_id = keycloak_openid_client.opencloud_web.id

  default_scopes = [
    "basic",
    "profile",
    "email",
    "roles",
    "groups",
    "web-origins",
    keycloak_openid_client_scope.opencloud_realm_roles.name
  ]
}

# ======================================================================================================================
# CLIENT: OpenCloudDesktop (public native client)
# ======================================================================================================================
resource "keycloak_openid_client" "opencloud_desktop" {
  realm_id    = keycloak_realm.nixpi.id
  client_id   = "OpenCloudDesktop"
  name        = "OpenCloud Desktop"
  description = "OpenCloud desktop sync client"

  access_type = "PUBLIC"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  use_refresh_tokens           = true
  pkce_code_challenge_method   = "S256"

  valid_redirect_uris = [
    "http://127.0.0.1",
    "http://localhost"
  ]

  web_origins = [
    "+"
  ]

  service_accounts_enabled = false
}

resource "keycloak_openid_client_default_scopes" "opencloud_desktop_default_scopes" {
  realm_id  = keycloak_realm.nixpi.id
  client_id = keycloak_openid_client.opencloud_desktop.id

  default_scopes = [
    "basic",
    "profile",
    "email",
    "roles",
    "groups",
    "web-origins",
    keycloak_openid_client_scope.opencloud_realm_roles.name
  ]
}

# ======================================================================================================================
# CLIENT: OpenCloudAndroid (public native client)
# ======================================================================================================================
resource "keycloak_openid_client" "opencloud_android" {
  realm_id    = keycloak_realm.nixpi.id
  client_id   = "OpenCloudAndroid"
  name        = "OpenCloud Android"
  description = "OpenCloud Android app"

  access_type = "PUBLIC"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  use_refresh_tokens           = true
  pkce_code_challenge_method   = "S256"

  valid_redirect_uris = [
    "oc://android.opencloud.eu"
  ]

  valid_post_logout_redirect_uris = [
    "oc://android.opencloud.eu"
  ]

  service_accounts_enabled = false
}

resource "keycloak_openid_client_default_scopes" "opencloud_android_default_scopes" {
  realm_id  = keycloak_realm.nixpi.id
  client_id = keycloak_openid_client.opencloud_android.id

  default_scopes = [
    "basic",
    "profile",
    "email",
    "roles",
    "groups",
    "web-origins",
    keycloak_openid_client_scope.opencloud_realm_roles.name
  ]
}

# ======================================================================================================================
# CLIENT: OpenCloudIOS (public native client)
# ======================================================================================================================
resource "keycloak_openid_client" "opencloud_ios" {
  realm_id    = keycloak_realm.nixpi.id
  client_id   = "OpenCloudIOS"
  name        = "OpenCloud iOS"
  description = "OpenCloud iOS app"

  access_type = "PUBLIC"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  use_refresh_tokens           = true
  pkce_code_challenge_method   = "S256"

  valid_redirect_uris = [
    "oc://ios.opencloud.eu"
  ]

  valid_post_logout_redirect_uris = [
    "oc://ios.opencloud.eu"
  ]

  service_accounts_enabled = false
}

resource "keycloak_openid_client_default_scopes" "opencloud_ios_default_scopes" {
  realm_id  = keycloak_realm.nixpi.id
  client_id = keycloak_openid_client.opencloud_ios.id

  default_scopes = [
    "basic",
    "profile",
    "email",
    "roles",
    "groups",
    "web-origins",
    keycloak_openid_client_scope.opencloud_realm_roles.name
  ]
}
