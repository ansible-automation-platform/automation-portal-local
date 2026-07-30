#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
RHDH_DIR="$ROOT_DIR/rhdh-local"

echo "=== Automation Portal Local — Cleanup ==="

# Stop services and remove volumes
if [ -f "$RHDH_DIR/compose.portal-apme.yaml" ]; then
  echo "Stopping services and removing volumes..."
  cd "$RHDH_DIR"
  podman compose -f compose.yaml -f compose.portal-apme.yaml down -v 2>/dev/null || true
  cd "$ROOT_DIR"
fi

# Remove overlay files copied into rhdh-local
echo "Removing overlay files from rhdh-local..."
rm -f "$RHDH_DIR/compose.portal-apme.yaml"
rm -f "$RHDH_DIR/configs/app-config/app-config.portal-apme.yaml"
rm -f "$RHDH_DIR/configs/dynamic-plugins/dynamic-plugins.portal-apme.yaml"
rm -f "$RHDH_DIR/.env"
rm -rf "$RHDH_DIR/local-plugins/portal-apme"

# Optionally remove APME images
if [ "${1:-}" = "--remove-images" ]; then
  echo "Removing APME container images..."
  APME_TAG="${APME_IMAGE_TAG:-latest}"
  for svc in gateway primary native opa ansible gitleaks collection-health dep-audit galaxy-proxy; do
    podman rmi "ghcr.io/ansible/apme-${svc}:${APME_TAG}" 2>/dev/null || true
  done
  podman rmi "postgres:16-alpine" 2>/dev/null || true
  echo "APME images removed."
fi

echo ""
echo "Cleanup complete."
echo "  To also remove APME container images: ./scripts/cleanup.sh --remove-images"
