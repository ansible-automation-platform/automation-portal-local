#!/bin/bash
# Pack portal plugin dist-dynamic directories into local-plugins/portal-apme/*.tgz
# and rewrite overlay/dynamic-plugins.portal-apme.yaml package filenames.
#
# Prerequisites: each plugin already has dist-dynamic/ (e.g. after yarn export-dynamic).
# This script is intentionally non-destructive — it does not run BUILD_TYPE=portal
# build.sh (that mode deletes plugins/backstage-rhaap from the clone).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

PLUGIN_REPO="${1:-}"
DEST_DIR="${2:-$ROOT_DIR/local-plugins/portal-apme}"
# Space-separated plugin directory names under plugins/
PLUGINS_LIST="${3:-}"

if [ -z "$PLUGIN_REPO" ] || [ -z "$PLUGINS_LIST" ]; then
  echo "Usage: $0 <path-to-ansible-backstage-plugins> <dest-dir> \"<plugin names>\""
  exit 1
fi

PLUGIN_REPO="$(cd "$PLUGIN_REPO" && pwd)"
mkdir -p "$DEST_DIR"
rm -f "$DEST_DIR"/*.tgz

PACKED=0
for name in $PLUGINS_LIST; do
  dist_dir="$PLUGIN_REPO/plugins/$name/dist-dynamic"
  if [ ! -f "$dist_dir/package.json" ]; then
    echo "ERROR: missing $dist_dir/package.json — export the plugin first." >&2
    exit 1
  fi
  echo "Packing $name…"
  (cd "$dist_dir" && npm pack --pack-destination "$DEST_DIR")
  PACKED=$((PACKED + 1))
done

PLUGINS_YAML="$ROOT_DIR/overlay/dynamic-plugins.portal-apme.yaml"
if [ -f "$PLUGINS_YAML" ]; then
  echo "Updating plugin references in dynamic-plugins.portal-apme.yaml…"
  for tgz in "$DEST_DIR"/*.tgz; do
    filename=$(basename "$tgz")
    # ansible-plugin-backstage-apme-dynamic-0.1.0-dev.abc123.tgz → ansible-plugin-backstage-apme-dynamic
    base=$(echo "$filename" | sed -E 's/-[0-9]+\.[0-9]+\.[0-9]+.*\.tgz$//')
    if [[ "${OSTYPE:-}" == darwin* ]]; then
      sed -i '' -E "s|${base}-[^ ]*\.tgz|${filename}|g" "$PLUGINS_YAML"
    else
      sed -i -E "s|${base}-[^ ]*\.tgz|${filename}|g" "$PLUGINS_YAML"
    fi
  done
fi

echo ""
echo "Packed $PACKED plugins into $DEST_DIR:"
ls -1 "$DEST_DIR"/*.tgz
echo "Source: $PLUGIN_REPO @ $(git -C "$PLUGIN_REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "$PLUGIN_REPO" status --porcelain 2>/dev/null || true)" ]; then
  echo "Note: PLUGIN_REPO has uncommitted changes — they are included in these tarballs."
fi
