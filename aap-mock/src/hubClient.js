import { upstreamContentRepo } from './hubRemotes.js';

/**
 * Upstream fetch + JSON link rewrite onto the mock host.
 */

async function authHeaders(remote) {
  if (typeof remote.getAuthHeaders === 'function') {
    return remote.getAuthHeaders();
  }
  if (!remote.token) return {};
  // Classic Hub API tokens (non-SSO). Console Hub offline tokens need SSO
  // exchange via createHubAccessTokenProvider → Bearer.
  return { Authorization: `Token ${remote.token}` };
}

/**
 * Rewrite absolute upstream URLs/paths so clients keep talking to the mock.
 *
 * Prefer *relative* `/api/galaxy/...` paths so both the browser
 * (`localhost:8099`) and the APME pod (`host.containers.internal:8099`)
 * resolve downloads against their own galaxy-server base URL.
 */
export function rewritePayload(value, { publicBase, upstreamBases, absolute = false }) {
  const bases = upstreamBases.map(b => b.replace(/\/$/, ''));
  const mock = (publicBase || '').replace(/\/$/, '');

  function toPahPath(path) {
    let p = path;
    if (p.startsWith('/api/automation-hub/')) {
      p = `/api/galaxy/${p.slice('/api/automation-hub/'.length)}`;
    }
    if (p.startsWith('/api/v3/') || p.startsWith('/api/pulp/')) {
      p = `/api/galaxy${p.slice(4)}`;
    } else if (p.startsWith('/api/content/')) {
      p = `/api/galaxy${p.slice(4)}`;
    } else if (p.startsWith('/v3/') || p.startsWith('/content/')) {
      p = `/api/galaxy${p}`;
    }
    return p;
  }

  function rewriteString(s) {
    let out = s;
    for (const base of bases) {
      if (out.startsWith(base)) {
        out = toPahPath(out.slice(base.length));
        if (absolute && mock) out = `${mock}${out}`;
        return out;
      }
    }
    // Relative pulp/galaxy/automation-hub paths that omit host
    if (
      out.startsWith('/api/v3/') ||
      out.startsWith('/api/pulp/') ||
      out.startsWith('/api/automation-hub/') ||
      out.startsWith('/api/content/') ||
      out.startsWith('/v3/') ||
      out.startsWith('/content/')
    ) {
      out = toPahPath(out);
      if (absolute && mock) out = `${mock}${out}`;
    }
    return out;
  }

  function walk(node) {
    if (node == null) return node;
    if (typeof node === 'string') return rewriteString(node);
    if (Array.isArray(node)) return node.map(walk);
    if (typeof node === 'object') {
      const out = {};
      for (const [k, v] of Object.entries(node)) {
        out[k] = walk(v);
      }
      return out;
    }
    return node;
  }

  return walk(value);
}

export async function upstreamFetch(remote, pathAndQuery, opts = {}) {
  const base = remote.base.replace(/\/$/, '');
  let path = pathAndQuery.startsWith('/') ? pathAndQuery : `/${pathAndQuery}`;
  const url = `${base}${path}`;
  const headers = {
    Accept: 'application/json',
    ...(await authHeaders(remote)),
    ...(opts.headers || {}),
  };
  const res = await fetch(url, {
    method: opts.method || 'GET',
    headers,
    redirect: 'manual',
  });
  return res;
}

/** Try several Hub search path shapes; Galaxy has a stable path. */
export async function searchCollectionOnRemote(remote, namespace, name, version) {
  const params = new URLSearchParams({
    namespace,
    name,
    limit: '1',
  });
  if (version) {
    params.set('version', version);
  } else {
    params.set('is_highest', 'true');
  }

  const upstreamRepo = upstreamContentRepo(remote);
  const candidates =
    remote.kind === 'galaxy'
      ? [`/api/v3/plugin/ansible/search/collection-versions/?${params}`]
      : [
          `/v3/plugin/ansible/search/collection-versions/?${params}`,
          `/api/v3/plugin/ansible/search/collection-versions/?${params}`,
          `/content/${upstreamRepo}/v3/plugin/ansible/search/collection-versions/?${params}`,
        ];

  for (const path of candidates) {
    let res;
    try {
      res = await upstreamFetch(remote, path);
    } catch {
      continue;
    }
    if (res.status === 401 || res.status === 403) {
      const err = new Error(
        `aap-mock: ${remote.id} auth failed (${res.status}). Set AAP_MOCK_HUB_TOKEN for certified/validated.`,
      );
      err.statusCode = res.status;
      err.remoteId = remote.id;
      throw err;
    }
    if (!res.ok) continue;
    const body = await res.json();
    const rows = body.data || body.results || [];
    if (!rows.length) continue;
    const row = rows[0];
    const cv = row.collection_version || row;
    return {
      namespace: cv.namespace || namespace,
      name: cv.name || name,
      version: cv.version,
      description: cv.description || '',
      remoteId: remote.id,
      contentRepo: remote.contentRepo,
      remoteBase: remote.base,
      kind: remote.kind,
    };
  }
  return null;
}
