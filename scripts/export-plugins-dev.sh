#!/bin/bash
# Export ansible-backstage-plugins into dist-dynamic for the mount-based DEV loop.
# Can run standalone or via: make export-plugins
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

if [[ -n "${1:-}" ]]; then
  PLUGIN_REPO="$1"
elif [[ -z "${PLUGIN_REPO:-}" ]]; then
  PLUGIN_REPO="$(resolve_plugin_repo)"
fi
export PLUGIN_REPO

if [[ -n "${SYNC_DEV_PLUGINS:-}" ]]; then
  PLUGINS="$SYNC_DEV_PLUGINS"
else
  # shellcheck disable=SC2207
  PLUGINS="$(resolve_portal_plugins "$PLUGIN_REPO")"
fi
export PLUGINS
export FORCE_EXPORT="${FORCE_EXPORT:-0}"

"$(cd "$(dirname "$0")" && pwd)/export-portal-plugins.sh"
