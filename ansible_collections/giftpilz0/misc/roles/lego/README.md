# lego role

Issues and renews ACME certificates with [Lego](https://go-acme.github.io/lego/)
on Linux and Windows. The role installs a daily renewal job at 03:00 with a
one-hour delay. Missing certificates are not issued during deployment unless
`lego_issue_on_deploy: true` is set.

Keep provider credentials and PFX passwords in Ansible Vault or another secret
store. `lego_certificates` is a list; every entry needs a unique `name`,
`domains`, and a `challenge`.

## Linux: Cloudflare certificate for Traefik

```yaml
lego_acme_email: admin@example.org
lego_certificates:
  - name: example-wildcard
    domains:
      - example.org
      - "*.example.org"
    challenge:
      type: dns-01
      provider: cloudflare
      environment:
        CLOUDFLARE_DNS_API_TOKEN: "{{ vault_cloudflare_dns_api_token }}"
    deploy:
      pem:
        directory: /etc/traefik/tls
        group: traefik
        directory_mode: "0750"
        certificate_mode: "0640"
        private_key_mode: "0640"
    hooks:
      changed:
        - type: command
          command: systemctl reload traefik
```

## Linux: acme-dns certificate for Nginx

```yaml
lego_certificates:
  - name: app
    domains:
      - app.example.org
    challenge:
      type: dns-01
      provider: acmedns
      environment:
        ACME_DNS_API_BASE: https://acme-dns.example.org
        ACME_DNS_STORAGE_PATH: /var/lib/lego/acme-dns-accounts.json
    deploy:
      pem:
        directory: /etc/nginx/tls/app
        group: nginx
    hooks:
      changed:
        - type: command
          command: systemctl reload nginx
```

The acme-dns account file is kept in the Lego state directory. Keep the
configured `ACME_DNS_STORAGE_PATH` stable so renewals reuse the registration.

## Linux: HTTP-01 certificate

```yaml
lego_certificates:
  - name: public-web
    domains:
      - www.example.org
    challenge:
      type: http-01
    deploy:
      pem:
        directory: /etc/ssl/public-web
        group: www-data
```

HTTP-01 requires port 80 and `/.well-known/acme-challenge/` to reach the host.
The role does not configure the web server or firewall.

## Windows: IIS certificate in the local machine store

```yaml
lego_acme_email: admin@example.org
lego_issue_on_deploy: true
lego_certificates:
  - name: portal
    domains:
      - portal.example.org
    challenge:
      type: dns-01
      provider: cloudflare
      environment:
        CLOUDFLARE_DNS_API_TOKEN: "{{ vault_cloudflare_dns_api_token }}"
    deploy:
      pfx:
        path: C:\ProgramData\lego\deploy\portal.pfx
        password: "{{ vault_portal_pfx_password }}"
      windows_store:
        store_location: LocalMachine
        store_name: My
    hooks:
      changed:
        - type: powershell
          script: |
            Import-Module WebAdministration
            Restart-WebAppPool -Name 'DefaultAppPool'
```

## Windows: application PFX without certificate-store import

```yaml
lego_certificates:
  - name: api
    domains:
      - api.example.org
    challenge:
      type: tls-alpn-01
    deploy:
      pfx:
        path: C:\ProgramData\api\tls\api.pfx
        password: "{{ vault_api_pfx_password }}"
    hooks:
      changed:
        - type: powershell
          script: Restart-Service -Name 'MyApiService'
```

## Advanced options

Use `renewal.threshold` for a certificate-specific threshold, `account_id`
when one email needs separate ACME accounts, and `extra_args` for Lego options
not covered by the schema:

```yaml
lego_certificates:
  - name: resolver-example
    domains:
      - example.org
    renewal:
      threshold: 14
    challenge:
      type: dns-01
      provider: cloudflare
      environment:
        CLOUDFLARE_DNS_API_TOKEN: "{{ vault_cloudflare_dns_api_token }}"
    extra_args:
      - --dns.propagation-wait
      - "60"
```
