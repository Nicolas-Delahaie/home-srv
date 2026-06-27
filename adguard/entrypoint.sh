#!/bin/sh
set -eu

template="/tmp/AdGuardHome.yaml"
output="/opt/adguardhome/conf/AdGuardHome.yaml"

vars=$(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$template" | sed 's/[${}]//g' | sort -u)
# No placeholders → config is static, copy as-is; missing env var → exit 1
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

exec /opt/adguardhome/AdGuardHome --config "$output" --work-dir /opt/adguardhome/work
