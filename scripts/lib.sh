#!/bin/bash
# Minimal shared helpers for scripts that may run standalone (outside Make).
# Primary orchestration logic lives in the top-level Makefile.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

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
