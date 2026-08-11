#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

command -v podman >/dev/null 2>&1 || { echo "ERROR: podman is required."; exit 1; }

if [ ! -f "$ROOT_DIR/.env" ]; then
  echo "ERROR: .env not found."
  echo "  cp .env.example .env"
  echo "  # Fill in AAP_HOST_URL, AAP_TOKEN, OAUTH credentials"
  exit 1
fi

PLUGIN_COUNT=$(find "$ROOT_DIR/local-plugins/portal" -name '*.tgz' 2>/dev/null | wc -l)
if [ "$PLUGIN_COUNT" -eq 0 ]; then
  echo "ERROR: No plugin tarballs found in local-plugins/portal/"
  exit 1
fi

if [ -d "$ROOT_DIR/images" ]; then
  "$SCRIPT_DIR/load-images.sh"
fi

cd "$ROOT_DIR"
podman compose -f compose.yaml -f compose.portal.yaml up -d

echo ""
echo "Portal is starting at http://localhost:7007"
echo "APME Gateway at http://localhost:8080"
echo "Stop: ./scripts/stop.sh"
