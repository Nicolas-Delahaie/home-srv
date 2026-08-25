#!/usr/bin/env bash
# Push openwu/presets.json into Open WebUI.
set -euo pipefail
cd "$(dirname "$0")/.."

docker compose exec -T openwu sh -c 'curl -sS --fail-with-body \
	-H "Authorization: Bearer $OPENWU_KEY" \
	-H "Content-Type: application/json" \
	-d @- http://localhost:8080/api/v1/models/import' < openwu/presets.json

echo
echo "presets pushed"
