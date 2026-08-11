#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGES_DIR="$ROOT_DIR/images"

echo "=== Loading Container Images ==="

if [ ! -d "$IMAGES_DIR" ]; then
  echo "No images/ directory found. Skipping image load."
  exit 0
fi

count=0
for archive in "$IMAGES_DIR"/*.tar.gz; do
  [ -f "$archive" ] || continue
  name=$(basename "$archive" .tar.gz)
  echo "Loading ${name}..."
  podman load < "$archive"
  count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
  echo "No .tar.gz archives found in images/."
else
  echo "Loaded ${count} container images."
fi
