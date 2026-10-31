set shell := ["bash", "-euo", "pipefail", "-c"]

# List recipes
default:
    @just --list --unsorted

# Run all linters and formatters (pre-commit); CI runs this too.
# External collections are installed like run.sh does, so ansible-lint resolves them.
lint *args:
    cd ansible-playbook && uv run ansible-galaxy collection install -r requirements.yaml -p .ansible/collections >/dev/null
    ANSIBLE_CONFIG=ansible-playbook/ansible.cfg pre-commit run --all-files {{args}}

# Definition of done
check: lint

# Run a playbook, e.g. `just deploy container --check` (see ansible-playbook/run.sh)
deploy *args:
    ansible-playbook/run.sh {{args}}

# Sync local DNS records to the UDM, plan by default (see dns/sync.sh)
dns *args:
    sops exec-env dns/secrets.sops.yaml 'dns/sync.sh {{args}}'
