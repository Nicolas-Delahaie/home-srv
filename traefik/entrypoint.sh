#!/bin/sh
set -eu

template="/etc/traefik/traefik_static.yml"
output="/etc/traefik/traefik.yml"
CURRENT_DATE="$(date +"%Y_%m_%d-%H_%M_%S")"
LOG_DIR="/logs"
export ACCESS_LOG_FILE="${LOG_DIR}/access_${CURRENT_DATE}.log"
export LOG_FILE="${LOG_DIR}/traefik_${CURRENT_DATE}.log"

vars=$(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$template" | sed 's/[${}]//g' | sort -u)
if [ -z "$vars" ]; then
    cp "$template" "$output"
else
    set --
    for v in $vars; do
        val=$(printenv "$v") || { echo "Missing env: $v" >&2; exit 1; }
        esc=$(printf '%s' "$val" | sed 's/[\\&|]/\\&/g')
        set -- "$@" -e "s|\\\${$v}|$esc|g"
    done
    sed "$@" "$template" > "$output"
fi

echo "Traefik log file: $LOG_FILE"
echo "Access log file: $ACCESS_LOG_FILE"

exec traefik