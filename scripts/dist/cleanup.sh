#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
[ -f "$ROOT_DIR/.env" ] && set -a && . "$ROOT_DIR/.env" && set +a
podman compose -f compose.yaml -f compose.portal.yaml down -v 2>/dev/null || true
if [ "${1:-}" = "--remove-images" ]; then
  APME_TAG="${APME_IMAGE_TAG:-latest}"
  for svc in gateway primary native opa ansible gitleaks collection-health dep-audit galaxy-proxy; do
    podman rmi "ghcr.io/ansible/apme-${svc}:${APME_TAG}" 2>/dev/null || true
  done
  podman rmi "postgres:16-alpine" 2>/dev/null || true
fi
echo "Cleanup complete."
