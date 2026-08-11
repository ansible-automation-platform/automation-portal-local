#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
[ -f "$ROOT_DIR/.env" ] && set -a && . "$ROOT_DIR/.env" && set +a
podman compose -f compose.yaml -f compose.portal.yaml down -v 2>/dev/null || true
if [ "${1:-}" = "--remove-images" ]; then
  podman rmi "postgres:16-alpine" 2>/dev/null || true
fi
echo "Cleanup complete."
