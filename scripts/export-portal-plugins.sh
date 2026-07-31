#!/bin/bash
# Export portal plugins from ansible-backstage-plugins into dist-dynamic.
#
# Incremental by default: skip a plugin when dist-dynamic/package.json is newer
# than that plugin's sources and its workspace/embed dependencies.
#
# Env:
#   PLUGIN_REPO   — path to ansible-backstage-plugins (required)
#   PLUGINS       — space-separated plugin directory names (required)
#   FORCE_EXPORT=1 — export every listed plugin (ignore stamps)
#   EXPORT_CLEAN=0 — use yarn export-dynamic without --clean (default: --clean)
#   EXPORT_DEV=1 — pass --dev (FE hot path)
#   DYNAMIC_PLUGINS_ROOT — with EXPORT_DEV=1, pass --dynamic-plugins-root <path>
#     On skip, sync dist-dynamic → that root so the browser still sees current bits.
set -euo pipefail

PLUGIN_REPO="${PLUGIN_REPO:?PLUGIN_REPO is required}"
PLUGINS_LIST="${PLUGINS:?PLUGINS is required}"
FORCE_EXPORT="${FORCE_EXPORT:-0}"
EXPORT_CLEAN="${EXPORT_CLEAN:-1}"
EXPORT_DEV="${EXPORT_DEV:-0}"
DYNAMIC_PLUGINS_ROOT="${DYNAMIC_PLUGINS_ROOT:-}"

PLUGIN_REPO="$(cd "$PLUGIN_REPO" && pwd)"
if [ -n "$DYNAMIC_PLUGINS_ROOT" ]; then
  mkdir -p "$DYNAMIC_PLUGINS_ROOT"
  DYNAMIC_PLUGINS_ROOT="$(cd "$DYNAMIC_PLUGINS_ROOT" && pwd)"
fi

# Workspace / embed packages that, when changed, invalidate consumers.
deps_for() {
  case "$1" in
    auth-backend-module-rhaap-provider|\
    catalog-backend-module-rhaap|\
    scaffolder-backend-module-backstage-rhaap|\
    self-service)
      echo "backstage-rhaap-common"
      ;;
    backstage-apme)
      echo "backstage-apme-common backstage-rhaap-common"
      ;;
    catalog-backend-module-apme)
      echo "backstage-apme-common backstage-rhaap-common"
      ;;
    *)
      echo ""
      ;;
  esac
}

# Newest mtime (epoch seconds) among files under the given paths.
newest_mtime() {
  local paths=("$@")
  local existing=()
  local p
  for p in "${paths[@]}"; do
    [ -e "$p" ] && existing+=("$p")
  done
  if [ "${#existing[@]}" -eq 0 ]; then
    echo 0
    return
  fi
  find "${existing[@]}" -type f \
    ! -path '*/node_modules/*' \
    ! -path '*/dist/*' \
    ! -path '*/dist-dynamic/*' \
    ! -path '*/.mf/*' \
    ! -path '*/tsconfig.tsbuildinfo' \
    -printf '%T@\n' 2>/dev/null \
    | sort -n | tail -1 | cut -d. -f1
}

stamp_mtime() {
  local stamp="$1"
  if [ -f "$stamp" ]; then
    stat -c '%Y' "$stamp" 2>/dev/null || stat -f '%m' "$stamp"
  else
    echo 0
  fi
}

# Directory name rhdh-cli --dev uses under DYNAMIC_PLUGINS_ROOT.
dev_root_dirname() {
  local stamp="$1"
  python3 - "$stamp" <<'PY'
import json, sys
name = json.load(open(sys.argv[1]))["name"]  # @ansible/plugin-backstage-apme-dynamic
name = name.lstrip("@").replace("/", "-")
if name.endswith("-dynamic"):
    name = name[: -len("-dynamic")]
print(name)
PY
}

# Cheap sync so skipped exports still refresh the --dev mount root.
sync_dev_root() {
  local name="$1"
  local src="$PLUGIN_REPO/plugins/$name"
  local stamp="$src/dist-dynamic/package.json"
  [ -n "$DYNAMIC_PLUGINS_ROOT" ] || return 0
  [ -f "$stamp" ] || return 0

  local dest_name dest
  dest_name="$(dev_root_dirname "$stamp")"
  dest="$DYNAMIC_PLUGINS_ROOT/$dest_name"
  mkdir -p "$dest"
  # Prefer rsync; fall back to cp -a.
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude node_modules \
      "$src/dist-dynamic/" "$dest/"
  else
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "$src/dist-dynamic/." "$dest/"
  fi
  chmod -R a+rX "$dest" 2>/dev/null || true
  echo "  ↳ synced → $dest"
}

needs_export() {
  local name="$1"
  local src="$PLUGIN_REPO/plugins/$name"
  local stamp="$src/dist-dynamic/package.json"

  if [ "$FORCE_EXPORT" = "1" ]; then
    return 0
  fi
  if [ ! -f "$stamp" ]; then
    return 0
  fi

  local watch=("$src/src" "$src/package.json")
  [ -f "$src/config.d.ts" ] && watch+=("$src/config.d.ts")
  [ -d "$src/templates" ] && watch+=("$src/templates")
  [ -d "$src/dev" ] && watch+=("$src/dev")

  local dep
  for dep in $(deps_for "$name"); do
    [ -d "$PLUGIN_REPO/plugins/$dep" ] && watch+=("$PLUGIN_REPO/plugins/$dep/src" "$PLUGIN_REPO/plugins/$dep/package.json")
  done

  local src_m stamp_m
  src_m="$(newest_mtime "${watch[@]}")"
  stamp_m="$(stamp_mtime "$stamp")"
  [ "${src_m:-0}" -gt "${stamp_m:-0}" ]
}

command -v yarn >/dev/null || { echo "ERROR: yarn is required"; exit 1; }

if [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
  # shellcheck disable=SC1090
  . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
  nvm use 22 >/dev/null 2>&1 || nvm use 20 >/dev/null 2>&1 || true
fi

export PATH="$PLUGIN_REPO/node_modules/.bin:$PATH"

if [ ! -d "$PLUGIN_REPO/node_modules" ]; then
  echo "Installing workspace deps (yarn)…"
  (cd "$PLUGIN_REPO" && yarn install)
fi

if [ "$EXPORT_DEV" = "1" ]; then
  echo "=== FE --dev export (incremental) ==="
  if [ -n "$DYNAMIC_PLUGINS_ROOT" ]; then
    echo "DYNAMIC_PLUGINS_ROOT=$DYNAMIC_PLUGINS_ROOT"
  fi
else
  echo "=== Export portal plugins (dist-dynamic) ==="
fi
echo "PLUGIN_REPO=$PLUGIN_REPO"
echo "Node: $(node -v 2>/dev/null || echo missing)"
if [ "$FORCE_EXPORT" = "1" ]; then
  echo "FORCE_EXPORT=1 — rebuilding all listed plugins"
else
  echo "Incremental — skip plugins with up-to-date dist-dynamic (FORCE_EXPORT=1 to rebuild all)"
fi
echo ""

EXPORTED=0
SKIPPED=0

for name in $PLUGINS_LIST; do
  src="$PLUGIN_REPO/plugins/$name"
  if [ ! -d "$src" ]; then
    echo "ERROR: missing plugin directory: $src" >&2
    exit 1
  fi

  if ! needs_export "$name"; then
    echo "✓ skip $name (dist-dynamic up to date)"
    if [ "$EXPORT_DEV" = "1" ] && [ -n "$DYNAMIC_PLUGINS_ROOT" ]; then
      sync_dev_root "$name"
    fi
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  extra_flags=()
  label="export-dynamic"
  if [ "$EXPORT_CLEAN" != "0" ]; then
    extra_flags+=(--clean)
    label="$label --clean"
  fi
  if [ "$EXPORT_DEV" = "1" ]; then
    extra_flags+=(--dev)
    label="$label --dev"
    if [ -n "$DYNAMIC_PLUGINS_ROOT" ]; then
      extra_flags+=(--dynamic-plugins-root "$DYNAMIC_PLUGINS_ROOT")
    fi
  fi

  echo "→ $label: $name"

  (
    cd "$src"
    if grep -q '"export-dynamic"' package.json 2>/dev/null; then
      yarn export-dynamic "${extra_flags[@]}"
    else
      yarn run --top-level janus-cli package export-dynamic-plugin "${extra_flags[@]}" 2>/dev/null \
        || rhdh-cli package export-dynamic-plugin "${extra_flags[@]}"
    fi
  )

  if [ ! -f "$src/dist-dynamic/package.json" ]; then
    echo "ERROR: $name export did not produce dist-dynamic/package.json" >&2
    exit 1
  fi
  EXPORTED=$((EXPORTED + 1))
done

if [ "$EXPORT_DEV" = "1" ] && [ -n "$DYNAMIC_PLUGINS_ROOT" ]; then
  chmod -R a+rX "$DYNAMIC_PLUGINS_ROOT" 2>/dev/null || true
fi

echo ""
echo "=== Export done (exported=$EXPORTED skipped=$SKIPPED) ==="
