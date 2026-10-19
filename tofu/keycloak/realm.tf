resource "keycloak_realm" "nixpi" {
  realm             = var.realm_name
  enabled           = true
  display_name      = var.realm_display_name
  display_name_html = "<b>${var.realm_display_name}</b>"
  login_theme       = "nixpi"

  # Authentication settings
  remember_me              = true
  login_with_email_allowed = true
  duplicate_emails_allowed = false
  registration_allowed     = false
  edit_username_allowed    = false
  reset_password_allowed   = true

  # Security settings
  ssl_required         = "external"
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

resource "keycloak_realm_events" "realm_events" {
  realm_id = keycloak_realm.nixpi.id

  events_enabled    = true
  events_expiration = 7889238 # 3 months

  admin_events_enabled         = true
  admin_events_details_enabled = true

  enabled_event_types = []

  events_listeners = [
    "jboss-logging"
  ]
}

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
