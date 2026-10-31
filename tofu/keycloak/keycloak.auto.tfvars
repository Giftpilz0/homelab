# OpenID clients, keyed by client ID.
# secret_key:    key in secrets.sops.yaml holding the client secret
# allowed_users: only these users may log in (enforced by a restricted browser flow)
clients = {
  "forgejo" = {
    name                            = "Forgejo"
    description                     = "Forgejo Git"
    secret_key                      = "forgejo_client_secret"
    valid_redirect_uris             = ["https://forgejo.nixpi.de/user/oauth2/keycloak/callback"]
    valid_post_logout_redirect_uris = ["https://forgejo.nixpi.de"]
    web_origins                     = ["https://forgejo.nixpi.de"]
    default_scopes                  = ["profile", "email", "forgejo-groups"]
    browser_1fa                     = true
  }

  "suwayomi" = {
    name                            = "Suwayomi"
    description                     = "Suwayomi reader"
    secret_key                      = "suwayomi_client_secret"
    pkce                            = true
    valid_redirect_uris             = ["https://suwayomi.nixpi.de/oidc/callback"]
    valid_post_logout_redirect_uris = ["https://suwayomi.nixpi.de/"]
    web_origins                     = ["https://suwayomi.nixpi.de"]
    default_scopes                  = ["profile", "email"]
    allowed_users                   = ["moritz"]
  }

  "music-webui" = {
    name                            = "Music Library WebUI"
    description                     = "Navidrome music library management"
    secret_key                      = "music_webui_client_secret"
    pkce                            = true
    valid_redirect_uris             = ["https://music.nixpi.de/oidc/callback"]
    valid_post_logout_redirect_uris = ["https://music.nixpi.de/"]
    web_origins                     = ["https://music.nixpi.de"]
    default_scopes                  = ["profile", "email"]
    allowed_users                   = ["moritz"]
  }

  "kartei" = {
    name                            = "kartei"
    description                     = "kartei flashcards"
    secret_key                      = "kartei_client_secret"
    pkce                            = true
    valid_redirect_uris             = ["https://kartei.nixpi.de/auth/callback"]
    valid_post_logout_redirect_uris = ["https://kartei.nixpi.de/"]
    web_origins                     = ["https://kartei.nixpi.de"]
    default_scopes                  = ["profile", "email"]
  }

  "beszel" = {
    name                            = "Beszel"
    description                     = "Beszel server monitoring"
    secret_key                      = "beszel_client_secret"
    valid_redirect_uris             = ["https://monitoring.nixpi.de/api/oauth2-redirect"]
    valid_post_logout_redirect_uris = ["https://monitoring.nixpi.de"]
    web_origins                     = ["https://monitoring.nixpi.de"]
    default_scopes                  = ["profile", "email"]
    allowed_users                   = ["moritz"]
  }

  "gatus" = {
    name                            = "Gatus"
    description                     = "Gatus status page"
    secret_key                      = "gatus_client_secret"
    valid_redirect_uris             = ["https://status.nixpi.de/authorization-code/callback"]
    valid_post_logout_redirect_uris = ["https://status.nixpi.de"]
    web_origins                     = ["https://status.nixpi.de"]
    default_scopes                  = ["profile", "email"]
    allowed_users                   = ["moritz"]
  }

  "vaultwarden" = {
    name                            = "Vaultwarden"
    description                     = "Vaultwarden password manager"
    secret_key                      = "vaultwarden_client_secret"
    valid_redirect_uris             = ["https://vaultwarden.nixpi.de/identity/connect/oidc-signin"]
    valid_post_logout_redirect_uris = ["https://vaultwarden.nixpi.de"]
    web_origins                     = ["https://vaultwarden.nixpi.de"]
    default_scopes                  = ["profile", "email"]
    browser_1fa                     = true
  }

  "OpenCloudWeb" = {
    name        = "OpenCloud Web"
    description = "OpenCloud web application"
    access_type = "PUBLIC"
    pkce        = true
    valid_redirect_uris = [
      "https://opencloud.nixpi.de/",
      "https://opencloud.nixpi.de/oidc-callback.html",
      "https://opencloud.nixpi.de/oidc-silent-redirect.html",
    ]
    valid_post_logout_redirect_uris = ["https://opencloud.nixpi.de", "https://opencloud.nixpi.de/*"]
    web_origins                     = ["https://opencloud.nixpi.de"]
    default_scopes                  = ["basic", "profile", "email", "roles", "groups", "web-origins", "opencloud-realm-roles"]
  }

  "OpenCloudDesktop" = {
    name                = "OpenCloud Desktop"
    description         = "OpenCloud desktop sync client"
    access_type         = "PUBLIC"
    pkce                = true
    valid_redirect_uris = ["http://127.0.0.1", "http://localhost"]
    web_origins         = ["+"]
    default_scopes      = ["basic", "profile", "email", "roles", "groups", "web-origins", "opencloud-realm-roles"]
  }

  "OpenCloudAndroid" = {
    name                            = "OpenCloud Android"
    description                     = "OpenCloud Android app"
    access_type                     = "PUBLIC"
    pkce                            = true
    valid_redirect_uris             = ["oc://android.opencloud.eu"]
    valid_post_logout_redirect_uris = ["oc://android.opencloud.eu"]
    default_scopes                  = ["basic", "profile", "email", "roles", "groups", "web-origins", "opencloud-realm-roles"]
  }

  "OpenCloudIOS" = {
    name                            = "OpenCloud iOS"
    description                     = "OpenCloud iOS app"
    access_type                     = "PUBLIC"
    pkce                            = true
    valid_redirect_uris             = ["oc://ios.opencloud.eu"]
    valid_post_logout_redirect_uris = ["oc://ios.opencloud.eu"]
    default_scopes                  = ["basic", "profile", "email", "roles", "groups", "web-origins", "opencloud-realm-roles"]
  }
}
