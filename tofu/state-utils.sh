#!/bin/bash
# Decrypt/encrypt the local state of the tofu projects (state.tfstate <-> state.tfstate.enc in git).
# usage: tofu/state-utils.sh decrypt|encrypt|status [project...]   (default: every project in tofu/)
set -euo pipefail

TOFU_DIR=$(cd "$(dirname "$0")" && pwd)
TMP=""
trap 'rm -f "$TMP"' EXIT INT TERM

usage() {
    echo "usage: $0 decrypt|encrypt|status [project...]" >&2
    exit 1
}

# Plain backups tofu leaves behind (apply, state rm/mv, import)
backups() {
    compgen -G '*.tfstate.backup' || true
    compgen -G '*.tfstate.*.backup' || true
}

decrypt() {
    if [ -f state.tfstate ]; then
        echo "  already decrypted"
    elif [ -f state.tfstate.enc ]; then
        TMP=$(mktemp)
        sops --decrypt --input-type json --output-type json state.tfstate.enc >"$TMP"
        mv "$TMP" state.tfstate
        echo "  🔓 state.tfstate.enc → state.tfstate"
    else
        echo "  no state"
    fi
}

encrypt() {
    if [ -f state.tfstate ]; then
        TMP=$(mktemp)
        # The input path selects the .sops.yaml creation rule (\.tfstate$)
        sops --encrypt --input-type json --output-type json state.tfstate >"$TMP"
        mv "$TMP" state.tfstate.enc
        rm -f state.tfstate
        echo "  🔒 state.tfstate → state.tfstate.enc"
    else
        echo "  nothing to encrypt"
    fi
    # Only clean up once the encrypted state exists
    if [ -f state.tfstate.enc ]; then
        backups | while read -r f; do
            rm -f "$f"
            echo "  removed plain $f"
        done
    fi
}

status() {
    local state="none"
    [ -f state.tfstate.enc ] && state="encrypted"
    [ -f state.tfstate ] && state="DECRYPTED (run encrypt before committing)"
    echo "  $state"
    backups | sed 's/^/  plain backup: /'
}

[ $# -ge 1 ] || usage
action=$1
shift
case "$action" in
    decrypt | encrypt) command -v sops >/dev/null || {
        echo "❌ sops not found" >&2
        exit 1
    } ;;
    status) ;;
    *) usage ;;
esac

if [ $# -eq 0 ]; then
    # shellcheck disable=SC2046 # word splitting intended: one argument per project dir
    set -- $(for f in "$TOFU_DIR"/*/versions.tf; do basename "$(dirname "$f")"; done)
fi

for project in "$@"; do
    [ -f "$TOFU_DIR/$project/versions.tf" ] || {
        echo "❌ unknown project: $project" >&2
        exit 1
    }
    echo "$project:"
    (cd "$TOFU_DIR/$project" && "$action")
done
