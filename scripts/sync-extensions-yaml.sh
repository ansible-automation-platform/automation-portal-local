#!/usr/bin/env bash
# Preserve click-install guests in dynamic-plugins.extensions.yaml.
# Tarball/extensions mode stores that file on the named volume, not the host
# bind-mount — keep both in sync and never reset plugins: [].
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RHDH_DIR="${1:-$ROOT_DIR/rhdh-local}"
HOST_YAML="$RHDH_DIR/dynamic-plugins-root/dynamic-plugins.extensions.yaml"

mkdir -p "$(dirname "$HOST_YAML")"

VOL="$(podman volume ls -q 2>/dev/null | grep -E '(^|_)dynamic-plugins-root$' | head -1 || true)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if [ -n "$VOL" ]; then
  if podman run --rm -v "$VOL:/dynamic-plugins-root" alpine \
      test -f /dynamic-plugins-root/dynamic-plugins.extensions.yaml; then
    podman run --rm -v "$VOL:/dynamic-plugins-root" alpine \
      cat /dynamic-plugins-root/dynamic-plugins.extensions.yaml > "$tmp"
    cp "$tmp" "$HOST_YAML"
    echo "Loaded click-install yaml from volume $VOL"
  fi
fi

python3 "$ROOT_DIR/scripts/ensure-extensions-yaml.py" \
  --catalog-index "$ROOT_DIR/overlay/catalog-index" \
  --file "$HOST_YAML"

if [ -n "$VOL" ]; then
  podman run --rm \
    -v "$VOL:/dynamic-plugins-root" \
    -v "$HOST_YAML":/src.yaml:ro,Z \
    alpine sh -c \
      'cp /src.yaml /dynamic-plugins-root/dynamic-plugins.extensions.yaml && chown 1001 /dynamic-plugins-root/dynamic-plugins.extensions.yaml && chmod 644 /dynamic-plugins-root/dynamic-plugins.extensions.yaml'
  echo "Wrote click-install yaml back to volume $VOL"
fi
