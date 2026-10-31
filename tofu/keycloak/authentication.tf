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

# Restricted browser flow, one per client with allowed_users.
# Logs in like "browser 1fa" (SSO cookie or password), then denies users without the client's "access" role.
# The check runs after the cookie step, so existing SSO sessions are checked too.
locals {
  restricted_clients = { for id, client in var.clients : id => client if length(client.allowed_users) > 0 }
}

resource "keycloak_authentication_flow" "restricted" {
  for_each = local.restricted_clients

  realm_id    = keycloak_realm.nixpi.id
  alias       = "browser restricted ${each.key}"
  description = "Browser flow that only admits members of ${each.key}-access"
}

resource "keycloak_authentication_subflow" "restricted_login" {
  for_each = local.restricted_clients

  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_flow.restricted[each.key].alias
  alias             = "${each.key} login"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution" "restricted_cookie" {
  for_each = local.restricted_clients

  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow.restricted_login[each.key].alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

resource "keycloak_authentication_subflow" "restricted_forms" {
  for_each = local.restricted_clients

  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow.restricted_login[each.key].alias
  alias             = "${each.key} forms"
  requirement       = "ALTERNATIVE"
  priority          = 20
}

resource "keycloak_authentication_execution" "restricted_password" {
  for_each = local.restricted_clients

  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow.restricted_forms[each.key].alias
  authenticator     = "auth-username-password-form"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_subflow" "restricted_check" {
  for_each = local.restricted_clients

  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_flow.restricted[each.key].alias
  alias             = "${each.key} access check"
  requirement       = "CONDITIONAL"
  priority          = 20
}

resource "keycloak_authentication_execution" "restricted_condition" {
  for_each = local.restricted_clients

  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow.restricted_check[each.key].alias
  authenticator     = "conditional-user-role"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "restricted_condition" {
  for_each = local.restricted_clients

  realm_id     = keycloak_realm.nixpi.id
  execution_id = keycloak_authentication_execution.restricted_condition[each.key].id
  alias        = "${each.key}-missing-access-role"
  config = {
    condUserRole = "${each.key}.access" # client role: <client id>.<role>
    negate       = "true"
  }
}

resource "keycloak_authentication_execution" "restricted_deny" {
  for_each = local.restricted_clients

  realm_id          = keycloak_realm.nixpi.id
  parent_flow_alias = keycloak_authentication_subflow.restricted_check[each.key].alias
  authenticator     = "deny-access-authenticator"
  requirement       = "REQUIRED"
  priority          = 20
}
