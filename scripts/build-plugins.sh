#!/bin/bash
# Build portal plugin tarballs from an ansible-backstage-plugins clone.
#
# Non-destructive: incremental export-dynamic + npm pack.
# Does NOT use BUILD_TYPE=portal ./build.sh (that deletes plugins/backstage-rhaap).
#
# Prefer: make build-plugins   or   make start  (start builds automatically)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DEST_DIR="$ROOT_DIR/local-plugins/portal-apme"

UPSTREAM_DIR="${1:-}"
BRANCH="${2:-}"

DEFAULT_PLUGINS="auth-backend-module-rhaap-provider catalog-backend-module-rhaap self-service scaffolder-backend-module-backstage-rhaap backstage-apme catalog-backend-module-apme"
PLUGINS_LIST="${PLUGINS:-$DEFAULT_PLUGINS}"

if [ -z "$UPSTREAM_DIR" ]; then
  echo "Usage: ./scripts/build-plugins.sh <path-to-ansible-backstage-plugins> [branch]"
  echo ""
  echo "Exports portal plugins (yarn export-dynamic) and packs .tgz into"
  echo "local-plugins/portal-apme/. Prefer: make build-plugins / make start"
  exit 1
fi

UPSTREAM_DIR="$(cd "$UPSTREAM_DIR" && pwd)"

if [ ! -d "$UPSTREAM_DIR/plugins" ]; then
  echo "ERROR: $UPSTREAM_DIR/plugins not found."
  echo "Are you pointing to the ansible-backstage-plugins repo?"
  exit 1
fi

if [ -n "$BRANCH" ]; then
  echo "Checking out branch: $BRANCH"
  git -C "$UPSTREAM_DIR" checkout "$BRANCH"
fi

echo "=== Building Portal Plugin Tarballs ==="
echo "Source:  $UPSTREAM_DIR"
echo "Branch:  $(git -C "$UPSTREAM_DIR" branch --show-current 2>/dev/null || echo unknown)"
echo "HEAD:    $(git -C "$UPSTREAM_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "Plugins: $PLUGINS_LIST"
echo ""

PLUGIN_REPO="$UPSTREAM_DIR" PLUGINS="$PLUGINS_LIST" FORCE_EXPORT="${FORCE_EXPORT:-0}" \
  "$SCRIPT_DIR/export-portal-plugins.sh"

"$SCRIPT_DIR/pack-portal-plugins.sh" "$UPSTREAM_DIR" "$DEST_DIR" "$PLUGINS_LIST"

echo ""
echo "Next: make start   # or SKIP_BUILD=1 if tarballs are already fresh"
