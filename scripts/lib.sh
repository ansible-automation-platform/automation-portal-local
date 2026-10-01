#!/bin/bash
# Minimal shared helpers for scripts that may run standalone (outside Make).
# Primary orchestration logic lives in the top-level Makefile.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Space-separated portal core plugins (no APME).
PORTAL_CORE_PLUGINS=(
  auth-backend-module-rhaap-provider
  catalog-backend-module-rhaap
  self-service
  scaffolder-backend-module-backstage-rhaap
  rhaap-app-auth
)

APME_PLUGIN_DIRS=(
  backstage-apme
  catalog-backend-module-apme
)

apme_plugins_in_repo() {
  local repo="${1:-}"
  [[ -n "$repo" && -f "$repo/plugins/backstage-apme/package.json" ]]
}

resolve_portal_plugins() {
  local repo="${1:-}"
  local plugins=("${PORTAL_CORE_PLUGINS[@]}")
  if apme_plugins_in_repo "$repo"; then
    plugins+=("${APME_PLUGIN_DIRS[@]}")
  fi
  echo "${plugins[@]}"
}

resolve_plugin_repo() {
  if [[ -f "$ROOT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ROOT_DIR/.env"
    set +a
  fi
  local candidate="${PLUGIN_REPO:-}"
  if [[ -z "$candidate" && -n "${1:-}" ]]; then
    candidate="$1"
  fi
  if [[ -z "$candidate" ]]; then
    candidate="$HOME/github/ansible-backstage-plugins"
  fi
  if [[ ! -d "$candidate" ]]; then
    echo "ERROR: PLUGIN_REPO not found: $candidate" >&2
    echo "Set PLUGIN_REPO in .env or pass the path as an argument." >&2
    exit 1
  fi
  # shellcheck disable=SC2164
  cd "$candidate"
  pwd
}
