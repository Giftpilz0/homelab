# OpenCloud maps the realm roles from the flat 'roles' claim.
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
  realm_id            = keycloak_realm.nixpi.id
  client_scope_id     = keycloak_openid_client_scope.opencloud_realm_roles.id
  name                = "realm-roles"
  claim_name          = "roles"
  multivalued         = true
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

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

# Requested by the OpenCloud clients
resource "keycloak_openid_client_scope" "groups" {
  realm_id    = keycloak_realm.nixpi.id
  name        = "groups"
  description = "Maps group memberships (name only, no path prefix)"
}

resource "keycloak_openid_group_membership_protocol_mapper" "groups_mapper" {
  realm_id            = keycloak_realm.nixpi.id
  client_scope_id     = keycloak_openid_client_scope.groups.id
  name                = "groups"
  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
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
  realm_id            = keycloak_realm.nixpi.id
  client_scope_id     = keycloak_openid_client_scope.forgejo_groups.id
  name                = "groups"
  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}
