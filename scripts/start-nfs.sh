#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
if [ "${PORTAL_ENV_LOADED:-0}" != 1 ] && [ -f .env ]; then
  set -a
  source .env
  set +a
fi
export AAP_MOCK
AAP_MOCK="$(node --input-type=module -e 'import {usesAapMock} from "./scripts/nfs-composition.mjs"; console.log(usesAapMock() ? "1" : "0")')"
COMPOSE_PROFILES=""
if [ "$AAP_MOCK" = 1 ]; then COMPOSE_PROFILES=mock; fi
export COMPOSE_PROFILES
# Resolve before exports or writes; reject invalid/conflicting selections early.
selected_plugins="$(node scripts/nfs-composition.mjs)"
compose_overlay="$(node --input-type=module -e 'import {resolveProfile,profilePaths} from "./scripts/nfs-composition.mjs"; console.log(profilePaths(resolveProfile()).compose)')"
if [ "${SKIP_EXPORT:-0}" != 1 ]; then
for item in $selected_plugins; do
  name="${item##*/}"
  if [ -n "${EXPORT_PLUGINS:-}" ]; then
    case " $EXPORT_PLUGINS " in *" $name "*) ;; *) continue ;; esac
  fi
  source_dir="$PLUGIN_REPO/workspaces/${item%/*}/plugins/$name"
  echo "Exporting $name (log: /tmp/anstrat-rhdh-export-$name.log)"
  (
    cd "$source_dir"
    NODE_TLS_REJECT_UNAUTHORIZED=1 yarn run export-dynamic --clean
  ) > "/tmp/anstrat-rhdh-export-$name.log" 2>&1 || { tail -40 "/tmp/anstrat-rhdh-export-$name.log"; exit 1; }
done
fi
node scripts/prepare-nfs.mjs
node scripts/check-nfs-parity.mjs
if [ "${NFS_PREPARE_ONLY:-0}" = 1 ]; then
  echo 'Native configuration prepared and parity checked; no services changed.'
  exit 0
fi
if [ "${NFS_PACKAGE_MODE:-workspace}" = packed ]; then
  node scripts/pack-nfs.mjs
fi
make _env-files _overlays AAP_MOCK="$AAP_MOCK"
cd rhdh-local
# Runtime containers retain bind mounts and --requires dependencies. Recreate
# only this checkout's app/installer; never remove database/mock containers or volumes.
for container in rhdh rhdh-plugins-installer; do
  if podman container exists "$container"; then
    container_directory="$(podman inspect "$container" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}')"
    test "$container_directory" = "$TASK_ROOT/rhdh-local" || {
      echo "Refusing to replace $container owned by $container_directory" >&2
      exit 1
    }
  fi
done
for container in rhdh rhdh-plugins-installer; do
  if podman container exists "$container"; then
    podman rm --force "$container"
  fi
done
podman compose -f compose.yaml -f compose.portal.yaml -f "../$compose_overlay" up -d --no-recreate db
# The mock is stateless and must pick up changed OAuth settings. Do not let
# Compose's dependency traversal recreate the persistent database container.
set -- install-dynamic-plugins
if [ "$AAP_MOCK" = 1 ]; then set -- aap-mock "$@"; fi
podman compose -f compose.yaml -f compose.portal.yaml -f "../$compose_overlay" up -d --no-deps "$@"
installer_status="$(podman wait rhdh-plugins-installer)"
test "$installer_status" = 0 || { echo "Plugin installer failed with exit $installer_status"; exit 1; }
node "$TASK_ROOT/scripts/refresh-nfs-cache.mjs"
# Prerequisites were started above and the installer already exited successfully.
# Dependency traversal here would run it again and overwrite refreshed metadata.
podman compose -f compose.yaml -f compose.portal.yaml -f "../$compose_overlay" up -d --no-deps --no-recreate rhdh
