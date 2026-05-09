#!/bin/bash
set -euo pipefail

STATE_FILE="./state.tfstate"
ENCRYPTED_STATE="./state.tfstate.enc"
TEMP_FILE=$(mktemp)

cleanup() {
    rm -f "$TEMP_FILE"
}
trap cleanup EXIT INT TERM

if ! command -v sops >/dev/null 2>&1; then
    echo "❌ sops not found" >&2
    exit 1
fi

if [ -f "$ENCRYPTED_STATE" ] && [ ! -f "$STATE_FILE" ]; then
    echo "🔓 Decrypting..."
    if sops --decrypt --input-type json --output-type json \
           "$ENCRYPTED_STATE" > "$TEMP_FILE"; then
        mv "$TEMP_FILE" "$STATE_FILE"
        rm -f "$ENCRYPTED_STATE"  # Remove encrypted after success
        echo "✓ Decrypted → $STATE_FILE"
    else
        echo "❌ Decryption failed" >&2
        exit 1
    fi

elif [ -f "$STATE_FILE" ] && [ ! -f "$ENCRYPTED_STATE" ]; then
    echo "🔒 Encrypting everything..."
    if sops --encrypt --input-type json --output-type json \
           "$STATE_FILE" > "$TEMP_FILE"; then
        mv "$TEMP_FILE" "$ENCRYPTED_STATE"
        rm -f "$STATE_FILE"  # Remove plain after success
        echo "✓ Encrypted → $ENCRYPTED_STATE"
    else
        echo "❌ Encryption failed" >&2
        exit 1
    fi

elif [ ! -f "$STATE_FILE" ] && [ ! -f "$ENCRYPTED_STATE" ]; then
    echo "ℹ️  No state files"
    exit 0

else
    echo "⚠️  Conflicting files - clean manually:" >&2
    ls -la "$STATE_FILE" "$ENCRYPTED_STATE" 2>/dev/null | head -2 || true
    exit 1
fi
