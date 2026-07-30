#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
RHDH_DIR="$ROOT_DIR/rhdh-local"

echo "=== Automation Portal Local — Stop ==="

if [ ! -f "$RHDH_DIR/compose.portal-apme.yaml" ]; then
  echo "Portal does not appear to be running (no compose overlay found)."
  exit 0
fi

cd "$RHDH_DIR"
podman compose -f compose.yaml -f compose.portal-apme.yaml down

echo "All services stopped."
