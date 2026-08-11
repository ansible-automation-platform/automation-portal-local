/**
 * Learned collection cache — source of truth for mock Galaxy search/list.
 */

export function createHubCache() {
  /** @type {Map<string, object>} */
  const byKey = new Map();

  function key(namespace, name, version) {
    const v = version || '*';
    return `${namespace}.${name}@${v}`.toLowerCase();
  }

  function put(entry) {
    const rec = {
      namespace: entry.namespace,
      name: entry.name,
      version: entry.version,
      description: entry.description || '',
      remoteId: entry.remoteId,
      contentRepo: entry.contentRepo,
      remoteBase: entry.remoteBase,
      kind: entry.kind,
      cachedAt: new Date().toISOString(),
    };
    byKey.set(key(rec.namespace, rec.name, rec.version), rec);
    // Also index latest alias for version-less lookups
    byKey.set(key(rec.namespace, rec.name, '*'), rec);
    return rec;
  }

  function get(namespace, name, version) {
    if (version) {
      return byKey.get(key(namespace, name, version)) || null;
    }
    return byKey.get(key(namespace, name, '*')) || null;
  }

  function list() {
    const seen = new Set();
    const out = [];
    for (const rec of byKey.values()) {
      const id = `${rec.namespace}.${rec.name}@${rec.version}`.toLowerCase();
      if (seen.has(id)) continue;
      seen.add(id);
      out.push(rec);
    }
    return out.sort((a, b) =>
      `${a.namespace}.${a.name}`.localeCompare(`${b.namespace}.${b.name}`),
    );
  }

  function clear() {
    byKey.clear();
  }

  function size() {
    return list().length;
  }

  return { put, get, list, clear, size };
}
