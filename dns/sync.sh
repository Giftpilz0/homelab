#!/bin/bash
# Sync A and CNAME records from records.conf to the UDM.
# usage: unifi_api_key=... dns/sync.sh [--apply] [--prune]
#   --apply  make the changes
#   --prune  also delete records under $zone that are not in records.conf
# Records outside $zone (e.g. the Ecovacs overrides for bumper) are never changed.
set -euo pipefail

: "${unifi_api_key:?set unifi_api_key, see the usage above}"

zone=nixpi.de
site=default
unifi_url=${unifi_url:-https://192.168.10.1}
records=$(dirname "$0")/records.conf
api_base=$unifi_url/proxy/network/integration/v1

apply=false
prune=false
for arg in "$@"; do
    case $arg in
        --apply) apply=true ;;
        --prune) prune=true ;;
        *)
            echo "usage: $0 [--apply] [--prune]" >&2
            exit 1
            ;;
    esac
done

# The UDM has a self-signed certificate. The key goes through a pipe to keep it out of `ps`.
api() {
    local method=$1 path=$2
    shift 2
    curl -sSk --fail-with-body --max-time 20 -X "$method" \
        -H @<(printf 'X-API-KEY: %s\n' "$unifi_api_key") \
        -H 'Accept: application/json' -H 'Content-Type: application/json' \
        "$@" "$api_base$path"
}

# <A|CNAME> <domain> <value> [id]
body() {
    jq -nc --arg type "$1" --arg domain "$2" --arg value "$3" --arg id "${4:-}" '
        {type: ($type + "_RECORD"), enabled: true, domain: $domain, ttlSeconds: 0}
        + (if $type == "A" then {ipv4Address: $value} else {targetDomain: $value} end)
        + (if $id != "" then {id: $id} else {} end)'
}

desired=$(grep -vE '^[[:space:]]*(#|$)' "$records" | jq -Rn '
    [inputs | [splits("[[:space:]]+")] | {type: .[0], domain: .[1], value: .[2], fields: length}]')
jq -e 'all(.fields == 3 and (.type == "A" or .type == "CNAME"))' <<<"$desired" >/dev/null ||
    {
        echo "$records: expected <A|CNAME> <name> <value> on every line" >&2
        exit 1
    }
jq -e '(map(.domain) | length) == (map(.domain) | unique | length)' <<<"$desired" >/dev/null ||
    {
        echo "$records: duplicate name" >&2
        exit 1
    }

site_id=$(api GET "/sites?limit=200" | jq -er --arg site "$site" '.data[] | select(.internalReference == $site) | .id')
policies=/sites/$site_id/dns/policies

existing='[]'
offset=0
while :; do
    page=$(api GET "$policies?offset=$offset&limit=200")
    existing=$(jq -c --argjson page "$page" '. + $page.data' <<<"$existing")
    offset=$((offset + 200))
    [ "$offset" -lt "$(jq '.totalCount' <<<"$page")" ] || break
done

# Only enabled A and CNAME records are compared, the rest is not ours.
current=$(jq -c '[.[]
    | select(.enabled and (.type == "A_RECORD" or .type == "CNAME_RECORD"))
    | {id, domain, type: (.type | rtrimstr("_RECORD")), value: (.ipv4Address // .targetDomain)}]' <<<"$existing")
jq -e '(map(.domain) | length) == (map(.domain) | unique | length)' <<<"$current" >/dev/null ||
    {
        echo "the UDM has several A/CNAME records for one name, fix them by hand:" >&2
        jq -r 'group_by(.domain)[] | select(length > 1)[] | "  \(.type) \(.domain) \(.value)"' <<<"$current" >&2
        exit 1
    }

# One line per action: <op> <type> <domain> <value> <id> <old value>
actions=$(jq -nr --argjson desired "$desired" --argjson current "$current" --arg zone ".$zone" --argjson prune "$prune" '
    ($current | map({key: .domain}+{value: .}) | from_entries) as $have
    | ($desired | map(.domain)) as $wanted
    | ($desired[] | . as $d | $have[$d.domain] as $c
        | if $c == null then ["create", $d.type, $d.domain, $d.value, "-", "-"]
          elif $c.type != $d.type then ["replace", $d.type, $d.domain, $d.value, $c.id, "\($c.type) \($c.value)"]
          elif $c.value != $d.value then ["update", $d.type, $d.domain, $d.value, $c.id, $c.value]
          else empty end),
      ($current[] | select(.domain as $n | $wanted | index($n) | not)
        | if $prune and (.domain | endswith($zone)) then ["delete", .type, .domain, .value, .id, "-"]
          else ["unmanaged", .type, .domain, .value, "-", "-"] end)
    | @tsv')

changes=0
while IFS=$'\t' read -r op type domain value id old; do
    case $op in
        create) echo "+ $type $domain $value" ;;
        update) echo "~ $type $domain $old -> $value" ;;
        replace) echo "~ $domain $old -> $type $value" ;;
        delete) echo "- $type $domain $value" ;;
        unmanaged)
            echo "? $type $domain $value (not in records.conf)"
            continue
            ;;
        *) continue ;;
    esac
    changes=$((changes + 1))

    if $apply; then
        case $op in
            create) api POST "$policies" -d "$(body "$type" "$domain" "$value")" >/dev/null ;;
            update) api PUT "$policies/$id" -d "$(body "$type" "$domain" "$value" "$id")" >/dev/null ;;
            replace)
                api DELETE "$policies/$id" >/dev/null
                api POST "$policies" -d "$(body "$type" "$domain" "$value")" >/dev/null
                ;;
            delete) api DELETE "$policies/$id" >/dev/null ;;
        esac
    fi
done <<<"$actions"

if $apply; then
    echo "$changes change(s) applied"
else
    echo "$changes change(s) planned, nothing applied (use --apply)"
fi
