#!/bin/bash
# Render app-config.portal.yaml for the RHDH container (portal vs portal+APME).
#
# Usage: render-app-config-portal.sh <PORTAL_ONLY: 0|1> <src> <dest>
#
# Portal-only (main branch without backstage-apme):
#   - Drops the APME register-git-repository catalog location (template not synced).
# APME enabled: copies source as-is; ansible.apme.enabled comes from APME_ENABLED env.
set -euo pipefail

PORTAL_ONLY="${1:-1}"
SRC="${2:?src}"
DEST="${3:?dest}"

cp "$SRC" "$DEST"

if [ "$PORTAL_ONLY" = "1" ]; then
  python3 - "$DEST" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
start = end = None
for idx, line in enumerate(lines):
    if "apme-register-git-repository" in line:
        for back in range(idx, max(idx - 12, -1), -1):
            if lines[back].rstrip() == "  - rules:":
                start = back
                break
        for fwd in range(idx, min(idx + 12, len(lines))):
            if lines[fwd].strip() == "type: file":
                end = fwd + 1
                break
        break

if start is not None and end is not None:
    path.write_text("".join(lines[:start] + lines[end:]), encoding="utf-8")
PY
fi
