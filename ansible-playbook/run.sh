#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

export ANSIBLE_PIPELINING=True

INVENTORIES=($(find "./inventories" -maxdepth 1 -type d | tail -n +2 | xargs -n1 basename | sort))

if [[ ${#INVENTORIES[@]} -eq 0 ]]; then
    echo -e "[${RED}✘${NC}] No inventories found"
    exit 1
fi

if [[ -n "$1" ]]; then
    INVENTORY_DIR="$1"
    if [[ ! -d "./inventories/$INVENTORY_DIR" ]]; then
        echo -e "[${RED}✘${NC}] Inventory '$INVENTORY_DIR' not found"
        exit 1
    fi
else
    INVENTORY_DIR=$(gum choose "${INVENTORIES[@]}" --header="Select inventory to run")
fi

decrypt_sops_files() {
    local sops_files=($(find "./inventories/$INVENTORY_DIR" -name "*.y*ml" -exec grep -l "ENC\[" {} \; 2>/dev/null || true))

    if [[ ${#sops_files[@]} -eq 0 ]]; then
        return 0
    fi

    if ! command -v sops &>/dev/null; then
        echo -e "[${RED}✘${NC}] SOPS required but not installed"
        exit 1
    fi

    echo -e "[${BLUE}ℹ${NC}] Decrypting ${#sops_files[@]} SOPS file(s) in-place..."
    for file in "${sops_files[@]}"; do
        sops --decrypt --in-place "$file" || {
            echo -e "[${RED}✘${NC}] Failed to decrypt $file"
            exit 1
        }
    done

    printf '%s\n' "${sops_files[@]}"
}

encrypt_sops_files() {
    while IFS= read -r file; do
        [[ -f "$file" ]] && sops --encrypt --in-place "$file"
    done
}

main() {
    gum confirm "Run playbook for '$INVENTORY_DIR'?" || exit 0

    echo -e "[${BLUE}ℹ${NC}] Installing Ansible requirements..."
    ansible-playbook "./requirements/install-requirements.yml" || {
        echo -e "[${RED}✘${NC}] Failed to install requirements"
        exit 1
    }

    local sops_files_list
    sops_files_list=$(mktemp)
    decrypt_sops_files > "$sops_files_list"

    trap "encrypt_sops_files < '$sops_files_list'; rm -f '$sops_files_list'" EXIT

    echo -e "[${BLUE}ℹ${NC}] Running playbook with decrypted secrets..."
    ansible-playbook "./inventories/$INVENTORY_DIR/playbook.yml" --ask-become-pass "$@" -i "./inventories/$INVENTORY_DIR/hosts/hosts.yml"

    echo -e "[${GREEN}✔${NC}] Playbook completed"
}

main "$@"
