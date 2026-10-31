resource "keycloak_openid_client" "clients" {
  for_each = var.clients

  realm_id    = keycloak_realm.nixpi.id
  client_id   = each.key
  name        = each.value.name
  description = each.value.description

  access_type   = each.value.access_type
  client_secret = each.value.secret_key == null ? null : local.secrets[each.value.secret_key]

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  use_refresh_tokens         = true
  pkce_code_challenge_method = each.value.pkce ? "S256" : null

  valid_redirect_uris             = each.value.valid_redirect_uris
  valid_post_logout_redirect_uris = each.value.valid_post_logout_redirect_uris
  web_origins                     = each.value.web_origins

  dynamic "authentication_flow_binding_overrides" {
    for_each = length(each.value.allowed_users) > 0 || each.value.browser_1fa ? [true] : []
    content {
      browser_id = (
        length(each.value.allowed_users) > 0
        ? keycloak_authentication_flow.restricted[each.key].id
        : keycloak_authentication_flow.browser_flow_2.id
      )
    }
  }
}

resource "keycloak_openid_client_default_scopes" "clients" {
  for_each = var.clients

  realm_id       = keycloak_realm.nixpi.id
  client_id      = keycloak_openid_client.clients[each.key].id
  default_scopes = each.value.default_scopes

  # Custom scopes are referenced by name in the clients variable.
  depends_on = [
    keycloak_openid_client_scope.groups,
    keycloak_openid_client_scope.forgejo_groups,
    keycloak_openid_client_scope.opencloud_realm_roles,
  ]
}

# Access control for clients with allowed_users: group "<client id>-access" grants the client role "access",
# which the restricted browser flow checks (see authentication.tf).
resource "keycloak_role" "client_access" {
  for_each = local.restricted_clients

  realm_id    = keycloak_realm.nixpi.id
  client_id   = keycloak_openid_client.clients[each.key].id
  name        = "access"
  description = "May log in to ${each.value.name}"
}

resource "keycloak_group" "client_access" {
  for_each = local.restricted_clients

  realm_id = keycloak_realm.nixpi.id
  name     = "${each.key}-access"
}

resource "keycloak_group_roles" "client_access" {
  for_each = local.restricted_clients

  realm_id = keycloak_realm.nixpi.id
  group_id = keycloak_group.client_access[each.key].id
  role_ids = [keycloak_role.client_access[each.key].id]
}

# Authoritative: users added to the group in the admin console are removed again.
resource "keycloak_group_memberships" "client_access" {
  for_each = local.restricted_clients

  realm_id = keycloak_realm.nixpi.id
  group_id = keycloak_group.client_access[each.key].id
  members  = each.value.allowed_users
}
