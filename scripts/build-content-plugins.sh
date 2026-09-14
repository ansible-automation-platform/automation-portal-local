#!/bin/bash
# Export and pack the automation content management plugins as dynamic plugins.
#
# Kept separate from export-portal-plugins.sh because these plugins live in their own
# repository, declare their own embed packages in each package.json `export-dynamic`
# script, and therefore need none of that script's per-plugin `deps_for` bookkeeping.
#
# Env:
#   CONTENT_PLUGIN_REPO — path to automation-content-plugins (required)
#   CONTENT_PLUGINS     — space-separated plugin directory names (required)
#   DEST                — directory to write .tgz files into (required)
#   FORCE_EXPORT=1      — re-export even when dist-dynamic looks current
set -euo pipefail

REPO="${CONTENT_PLUGIN_REPO:?CONTENT_PLUGIN_REPO is required}"
PLUGINS_LIST="${CONTENT_PLUGINS:?CONTENT_PLUGINS is required}"
DEST="${DEST:?DEST is required}"
FORCE_EXPORT="${FORCE_EXPORT:-0}"

command -v yarn >/dev/null || { echo "ERROR: yarn required"; exit 1; }
command -v npm  >/dev/null || { echo "ERROR: npm required"; exit 1; }

[ -d "$REPO" ] || { echo "ERROR: CONTENT_PLUGIN_REPO not found: $REPO"; exit 1; }
REPO="$(cd "$REPO" && pwd)"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

# Package name for a plugin directory, read from its own manifest rather than guessed.
pkg_name() {
  node -e "process.stdout.write(require('$REPO/plugins/$1/package.json').name)"
}

needs_export() {
  local dir="$REPO/plugins/$1"
  [ "$FORCE_EXPORT" = "1" ] && return 0
  [ -f "$dir/dist-dynamic/package.json" ] || return 0
  # Re-export when any source file is newer than the last export.
  [ -n "$(find "$dir/src" -newer "$dir/dist-dynamic/package.json" -type f -print -quit 2>/dev/null)" ]
}

echo "=== Export content management plugins ==="
for plugin in $PLUGINS_LIST; do
  dir="$REPO/plugins/$plugin"
  [ -d "$dir" ] || { echo "ERROR: no such plugin: $dir"; exit 1; }

  name="$(pkg_name "$plugin")"
  if needs_export "$plugin"; then
    # Remove the previous export first. rhdh-cli runs `yarn install --immutable`
    # inside dist-dynamic, and a lockfile left over from an earlier export fails that
    # check as soon as an embedded package's content hash changes.
    rm -rf "$dir/dist-dynamic"
    echo "--- exporting $name"
    (cd "$REPO" && yarn workspace "$name" export-dynamic >/dev/null)
  else
    echo "--- $name up to date"
  fi
done

echo "=== Pack content management plugin tarballs ==="
for plugin in $PLUGINS_LIST; do
  dist="$REPO/plugins/$plugin/dist-dynamic"
  [ -d "$dist" ] || { echo "ERROR: missing dist-dynamic for $plugin"; exit 1; }
  # Remove any previous tarball for this plugin so stale versions cannot linger.
  name="$(pkg_name "$plugin")"
  slug="$(printf '%s' "$name" | sed 's|^@||; s|/|-|')"
  rm -f "$DEST/${slug}-dynamic-"*.tgz
  (cd "$dist" && npm pack --pack-destination "$DEST" >/dev/null)
  echo "--- packed $name"
done

echo "Tarballs in $DEST:"
ls -1 "$DEST"/*.tgz 2>/dev/null || true
