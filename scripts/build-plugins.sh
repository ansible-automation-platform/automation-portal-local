#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DEST_DIR="$ROOT_DIR/local-plugins/portal-apme"

UPSTREAM_DIR="${1:-}"
BRANCH="${2:-}"

if [ -z "$UPSTREAM_DIR" ]; then
  echo "Usage: ./scripts/build-plugins.sh <path-to-ansible-backstage-plugins> [branch]"
  echo ""
  echo "Builds dynamic plugin tarballs using the upstream repo's own build.sh"
  echo "with BUILD_TYPE=portal, then copies the packed tarballs here."
  echo ""
  echo "Examples:"
  echo "  ./scripts/build-plugins.sh ../ansible-backstage-plugins"
  echo "  ./scripts/build-plugins.sh ../ansible-backstage-plugins feat/apme-eap-next-ui-workflow"
  exit 1
fi

UPSTREAM_DIR="$(cd "$UPSTREAM_DIR" && pwd)"

if [ ! -f "$UPSTREAM_DIR/build.sh" ]; then
  echo "ERROR: $UPSTREAM_DIR/build.sh not found."
  echo "Are you pointing to the ansible-backstage-plugins repo?"
  exit 1
fi

# Switch branch if specified
if [ -n "$BRANCH" ]; then
  echo "Checking out branch: $BRANCH"
  git -C "$UPSTREAM_DIR" checkout "$BRANCH"
fi

echo "=== Building Portal Plugins ==="
echo "Source:  $UPSTREAM_DIR"
echo "Branch:  $(git -C "$UPSTREAM_DIR" branch --show-current)"
echo "HEAD:    $(git -C "$UPSTREAM_DIR" rev-parse --short HEAD)"
echo ""

# Run the upstream build.sh with BUILD_TYPE=portal
# This uses the repo's own build/export/pack logic — no duplication.
cd "$UPSTREAM_DIR"
BUILD_TYPE=portal bash build.sh

# Collect the packed tarballs from dist-dynamic directories
mkdir -p "$DEST_DIR"
rm -f "$DEST_DIR"/*.tgz

PACKED=0
for dist_dir in plugins/*/dist-dynamic; do
  [ -d "$dist_dir" ] || continue
  plugin_name=$(basename "$(dirname "$dist_dir")")
  echo "Packing $plugin_name..."
  (cd "$dist_dir" && npm pack --pack-destination "$DEST_DIR")
  PACKED=$((PACKED + 1))
done

# Update dynamic-plugins.portal-apme.yaml with actual tarball filenames
PLUGINS_YAML="$ROOT_DIR/overlay/dynamic-plugins.portal-apme.yaml"
if [ -f "$PLUGINS_YAML" ]; then
  echo "Updating plugin references in dynamic-plugins.portal-apme.yaml..."
  for tgz in "$DEST_DIR"/*.tgz; do
    filename=$(basename "$tgz")
    # Extract the base name without version (e.g. "ansible-plugin-backstage-self-service-dynamic")
    # Match any existing version of this plugin in the YAML
    base=$(echo "$filename" | sed -E 's/-[0-9]+\.[0-9]+\.[0-9]+.*\.tgz$//')
    sed -i '' -E "s|${base}-[^ ]*\.tgz|${filename}|g" "$PLUGINS_YAML"
  done
fi

echo ""
echo "=== Done ==="
echo "Built $PACKED plugins into $DEST_DIR:"
ls -1 "$DEST_DIR"/*.tgz
echo ""
echo "Next: ./scripts/start.sh"
