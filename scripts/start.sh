#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
RHDH_DIR="$ROOT_DIR/rhdh-local"

echo "=== Automation Portal Local — Start ==="

# Validate prerequisites
command -v podman >/dev/null 2>&1 || { echo "ERROR: podman is required. Install it first."; exit 1; }
command -v git >/dev/null 2>&1 || { echo "ERROR: git is required."; exit 1; }

if [ ! -f "$ROOT_DIR/.env" ]; then
  echo "ERROR: .env not found."
  echo "  cp .env.example .env"
  echo "  # Then fill in your AAP_HOST_URL, AAP_TOKEN, OAUTH credentials, etc."
  exit 1
fi

# Init submodule if needed
if [ ! -f "$RHDH_DIR/compose.yaml" ]; then
  echo "Initializing rhdh-local submodule..."
  git -C "$ROOT_DIR" submodule update --init --recursive
fi

# Copy overlay files into rhdh-local expected locations
echo "Copying overlay configuration..."
cp "$ROOT_DIR/overlay/app-config.portal-apme.yaml" \
   "$RHDH_DIR/configs/app-config/app-config.portal-apme.yaml"
cp "$ROOT_DIR/overlay/dynamic-plugins.portal-apme.yaml" \
   "$RHDH_DIR/configs/dynamic-plugins/dynamic-plugins.portal-apme.yaml"
cp "$ROOT_DIR/overlay/compose.portal-apme.yaml" \
   "$RHDH_DIR/compose.portal-apme.yaml"

# Copy plugin tarballs (clean destination first to avoid stale versions)
mkdir -p "$RHDH_DIR/local-plugins/portal-apme"
rm -f "$RHDH_DIR/local-plugins/portal-apme/"*.tgz 2>/dev/null
if ls "$ROOT_DIR/local-plugins/portal-apme/"*.tgz 1>/dev/null 2>&1; then
  cp "$ROOT_DIR/local-plugins/portal-apme/"*.tgz "$RHDH_DIR/local-plugins/portal-apme/"
  echo "Copied plugin tarballs:"
  ls -1 "$RHDH_DIR/local-plugins/portal-apme/"*.tgz
else
  echo "ERROR: No plugin tarballs found in local-plugins/portal-apme/"
  echo ""
  echo "Get plugins by one of:"
  echo "  1. Build from upstream:  ./scripts/build-plugins.sh <path-to-upstream>"
  echo "  2. Download from CI:     See README.md 'Option B: Download from GitHub Actions workflow'"
  exit 1
fi

# Auto-detect architecture: APME images are amd64-only, so on ARM hosts
# (macOS Apple Silicon) we need APME_PLATFORM for emulation.
# Written to a separate .env.platform file to avoid mutating user's .env.
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
  cat > "$ROOT_DIR/.env.platform" <<ARMEOF
APME_PLATFORM=linux/amd64
OPENSSL_CONF=/dev/null
ARMEOF
  echo "Detected ARM host — APME containers will use amd64 emulation"
else
  : > "$ROOT_DIR/.env.platform"
fi

# Merge .env + .env.platform into rhdh-local
cat "$ROOT_DIR/.env" "$ROOT_DIR/.env.platform" > "$RHDH_DIR/.env"

# Load APME images if OCI archives exist (distributable tar scenario)
if [ -d "$ROOT_DIR/images" ] && ls "$ROOT_DIR/images/"*.tar.gz 1>/dev/null 2>&1; then
  echo "Loading APME container images from archives..."
  "$SCRIPT_DIR/load-images.sh"
fi

# Start compose
echo "Starting services..."
cd "$RHDH_DIR"
podman compose -f compose.yaml -f compose.portal-apme.yaml up -d

echo ""
echo "=== Portal is starting ==="
echo "  Portal UI:     http://localhost:7007"
echo "  APME Gateway:  http://localhost:8080"
echo ""
echo "  View logs:     cd rhdh-local && podman compose -f compose.yaml -f compose.portal-apme.yaml logs -f"
echo "  Stop:          ./scripts/stop.sh"
