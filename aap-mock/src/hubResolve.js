/**
 * On-demand cascade resolve: certified → validated → galaxy.
 */

import { searchCollectionOnRemote } from './hubClient.js';

/**
 * @returns {Promise<object|null>}
 */
export async function resolveCollection({
  remotes,
  cache,
  namespace,
  name,
  version,
  log,
  searchFn = searchCollectionOnRemote,
}) {
  const cached = cache.get(namespace, name, version);
  if (cached) {
    return { entry: cached, fromCache: true };
  }

  const authErrors = [];
  for (const remote of remotes) {
    if (remote.kind === 'hub' && !remote.token) {
      log?.info?.(
        `aap-mock hub: skip ${remote.id} (no AAP_MOCK_HUB_TOKEN)`,
      );
      continue;
    }
    try {
      const found = await searchFn(remote, namespace, name, version);
      if (found) {
        const entry = cache.put(found);
        log?.info?.(
          `aap-mock hub: resolved ${namespace}.${name}:${entry.version} via ${remote.id}`,
        );
        return { entry, fromCache: false };
      }
    } catch (err) {
      if (err.statusCode === 401 || err.statusCode === 403) {
        authErrors.push(err);
        log?.warn?.(err.message);
        continue;
      }
      log?.warn?.(
        `aap-mock hub: ${remote.id} resolve error: ${err.message}`,
      );
    }
  }

  return { entry: null, fromCache: false, authErrors };
}
