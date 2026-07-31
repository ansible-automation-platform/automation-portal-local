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

PLUGINS="${SYNC_DEV_PLUGINS:-auth-backend-module-rhaap-provider catalog-backend-module-rhaap self-service scaffolder-backend-module-backstage-rhaap backstage-apme catalog-backend-module-apme}"
export PLUGINS
export FORCE_EXPORT="${FORCE_EXPORT:-0}"

"$(cd "$(dirname "$0")" && pwd)/export-portal-plugins.sh"
