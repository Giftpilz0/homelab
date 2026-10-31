#!/usr/bin/env bash
# Usage: ./run.sh [--skip-collections] [inventory] [--playbook <file>] [ansible-playbook args...]
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

info() { echo -e "[\033[0;34mℹ\033[0m] $*"; }
fail() {
    echo -e "[\033[0;31m✘\033[0m] $*" >&2
    exit 1
}

skip_collections=false
if [[ ${1:-} == "--skip-collections" ]]; then
    skip_collections=true
    shift
fi

command -v uv >/dev/null || fail "uv is required (https://docs.astral.sh/uv/)"
if [[ -n "$(find inventories -name '*.sops.y*ml' -print -quit)" ]]; then
    command -v sops >/dev/null || fail "sops is required to decrypt inventory secrets"
fi

mapfile -t inventories < <(find inventories -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

if [[ -n ${1:-} && $1 != -* ]]; then
    inventory="$1"
    shift
elif command -v gum >/dev/null; then
    inventory=$(gum choose --header="Select inventory to run" "${inventories[@]}")
else
    fail "No inventory given. Available: ${inventories[*]}"
fi
[[ -d "inventories/$inventory" ]] || fail "Inventory '$inventory' not found. Available: ${inventories[*]}"

playbook=playbook.yaml
if [[ ${1:-} == "--playbook" ]]; then
    playbook="${2:?--playbook needs a file in inventories/$inventory}"
    shift 2
fi
[[ -f "inventories/$inventory/$playbook" ]] || fail "Playbook 'inventories/$inventory/$playbook' not found"

info "Syncing Python environment..."
uv sync --locked --quiet

galaxy_install() {
    local log
    log=$(mktemp)
    if ! uv run ansible-galaxy collection install -r requirements.yaml -p "$collections_dir" >"$log" 2>&1; then
        cat "$log" >&2
        rm -f "$log"
        fail "Collection install failed"
    fi
    rm -f "$log"
}

# Reinstall from scratch whenever requirements.yaml changed: pins apply exactly and removed
# collections disappear (ansible-galaxy never uninstalls). Git/URL/dir sources can change
# without that file changing; galaxy reinstalls those on every run.
collections_dir=.ansible/collections
stamp="$collections_dir/.requirements.sha256"
if [[ $skip_collections == false && -f requirements.yaml ]]; then
    if ! sha256sum --check --status "$stamp" 2>/dev/null; then
        info "Installing Ansible collections..."
        rm -rf "$collections_dir"
        galaxy_install
        sha256sum requirements.yaml >"$stamp"
    elif grep -qE '^\s*type:\s*(git|url|dir|file|subdirs)\b|git\+|\.git(#|\s|$)' requirements.yaml; then
        info "Updating git/url/dir collections..."
        galaxy_install
    else
        info "Ansible collections up to date"
    fi
fi

info "Running playbook for '$inventory'..."
exec uv run ansible-playbook \
    -i "inventories/$inventory/hosts/hosts.yaml" \
    "inventories/$inventory/$playbook" \
    --ask-become-pass "$@"
