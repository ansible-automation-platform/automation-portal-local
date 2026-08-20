#!/usr/bin/env bash
# Build (and optionally push) the extra catalog index image.
#
# Required (or set in .env):
#   EXTENSIONS_CATALOG_INDEX  quay.io/<ns>/portal-plugin-catalog-index:dev
#   APME_FRONTEND_OCI         quay.io/<ns>/plugin-backstage-apme:dev
#   APME_BACKEND_OCI          quay.io/<ns>/plugin-catalog-backend-module-apme:dev
#
# Optional:
#   SKIP_PUSH=1               build only (init container still needs a pullable tag)
#   APME_FRONTEND_LAYER       OCI path after ! (default: ansible-plugin-backstage-apme)
#   APME_BACKEND_LAYER        OCI path after ! (default: ansible-backstage-plugin-catalog-backend-module-apme)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT_DIR}/overlay/catalog-index"
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

: "${EXTENSIONS_CATALOG_INDEX:?Set EXTENSIONS_CATALOG_INDEX=quay.io/<ns>/portal-plugin-catalog-index:dev}"
: "${APME_FRONTEND_OCI:?Set APME_FRONTEND_OCI=quay.io/<ns>/plugin-backstage-apme:dev}"
: "${APME_BACKEND_OCI:?Set APME_BACKEND_OCI=quay.io/<ns>/plugin-catalog-backend-module-apme:dev}"

APME_FRONTEND_LAYER="${APME_FRONTEND_LAYER:-ansible-plugin-backstage-apme}"
APME_BACKEND_LAYER="${APME_BACKEND_LAYER:-ansible-backstage-plugin-catalog-backend-module-apme}"

# Strip accidental oci:// prefixes; keep an existing !layer if the caller set one.
_oci_ref() {
  local v="$1"
  local layer="$2"
  v="${v#oci://}"
  if [[ "${v}" == *'!'* ]]; then
    printf 'oci://%s' "${v}"
  else
    printf 'oci://%s!%s' "${v}" "${layer}"
  fi
}

FE="$(_oci_ref "${APME_FRONTEND_OCI}" "${APME_FRONTEND_LAYER}")"
BE="$(_oci_ref "${APME_BACKEND_OCI}" "${APME_BACKEND_LAYER}")"

cp -a "${SRC}/." "${STAGING}/"

python3 - "${STAGING}" "${FE}" "${BE}" <<'PY'
import sys
from pathlib import Path

root, fe, be = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
for path in root.rglob("*.yaml"):
    text = path.read_text(encoding="utf-8")
    updated = text.replace("oci://APME_FRONTEND_OCI", fe).replace("oci://APME_BACKEND_OCI", be)
    if updated != text:
        path.write_text(updated, encoding="utf-8")
        print(f"  substituted OCI refs in {path.relative_to(root)}")
PY

echo "Building ${EXTENSIONS_CATALOG_INDEX}"
podman build -f "${STAGING}/Containerfile" -t "${EXTENSIONS_CATALOG_INDEX}" "${STAGING}"

if [ "${SKIP_PUSH:-0}" = "1" ]; then
  echo "SKIP_PUSH=1 — image is local only. install-dynamic-plugins pulls via skopeo;"
  echo "  push this tag to a registry the container can reach."
  exit 0
fi

echo "Pushing ${EXTENSIONS_CATALOG_INDEX}"
podman push "${EXTENSIONS_CATALOG_INDEX}"
echo "Index ready. Run: make extensions EXTENSIONS_CATALOG_INDEX=${EXTENSIONS_CATALOG_INDEX}"
