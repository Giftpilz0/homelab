#!/bin/bash

set -e  # Exit on any error

# Configuration from environment variables
DOMAINS=$DOMAIN
CLOUDFLARE_DNS_API_TOKEN=$CLOUDFLARE_DNS_API_TOKEN

# Loop through all domains passed via DOMAIN environment variable
for DOMAIN in $DOMAINS; do

    CERT_FILE="/etc/ssl/lego/certificates/${DOMAIN}.crt"

    # Check if the certificate exists
    if [ ! -f "$CERT_FILE" ]; then
        echo "Certificate for $DOMAIN does not exist. Ordering a new one..."
        CLOUDFLARE_DNS_API_TOKEN=$CLOUDFLARE_DNS_API_TOKEN $LEGO_BIN \
            --pem \
            --email "$EMAIL" \
            --accept-tos \
            --dns "$DNS_PROVIDER" \
            --domains "$DOMAIN" \
            --key-type "$KEY_TYPE" \
            --dns.resolvers "$DNS_RESOLVER" \
            --path "$LEGO_PATH" \
            run
    else
        echo "Checking expiry for $DOMAIN..."
        # Check if the certificate is expiring soon (30 days threshold)
        if ! openssl x509 -checkend 2592000 -noout -in "$CERT_FILE"; then
            echo "Certificate for $DOMAIN is expiring soon. Renewing..."
            CLOUDFLARE_DNS_API_TOKEN=$CLOUDFLARE_DNS_API_TOKEN $LEGO_BIN \
                --pem \
                --email "$EMAIL" \
                --accept-tos \
                --dns "$DNS_PROVIDER" \
                --domains "$DOMAIN" \
                --key-type "$KEY_TYPE" \
                --dns.resolvers "$DNS_RESOLVER" \
                --path "$LEGO_PATH" \
                renew
        else
            echo "Certificate for $DOMAIN is still valid."
        fi
    fi
done

echo "Certificate management completed."
