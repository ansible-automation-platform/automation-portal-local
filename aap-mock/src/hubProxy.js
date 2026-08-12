/**
 * PAH-shaped Galaxy routes: cache search, content proxy, pulp repos.
 */

import { rewritePayload, upstreamFetch } from './hubClient.js';
import { resolveCollection } from './hubResolve.js';
import { getPahRepositoryNames, upstreamContentRepo } from './hubRemotes.js';

function galaxyPathFromPah(urlPath) {
  // /api/galaxy/v3/... -> /api/v3/...
  // /api/galaxy/pulp/... -> /api/pulp/...
  // /api/galaxy/content/... -> handled separately
  if (urlPath.startsWith('/api/galaxy/v3/')) {
    return `/api/v3/${urlPath.slice('/api/galaxy/v3/'.length)}`;
  }
  if (urlPath.startsWith('/api/galaxy/pulp/')) {
    return `/api/pulp/${urlPath.slice('/api/galaxy/pulp/'.length)}`;
  }
  return null;
}

function hubPathCandidates(remote, pahContentPath) {
  // pahContentPath like /api/galaxy/content/community/collections/...
  const m = pahContentPath.match(
    /^\/api\/galaxy\/content\/[^/]+\/(.*)$/,
  );
  const rest = m ? m[1] : '';
  if (remote.kind === 'galaxy') {
    const segment = upstreamContentRepo(remote);
    return [
      `/api/v3/plugin/ansible/content/${segment}/${rest}`,
      `/api/content/${segment}/${rest}`,
    ];
  }
  // Console Hub: metadata may live under rh-certified/validated content roots,
  // but collection *artifacts* (and often index JSON) are under published/.
  const repos = [remote.contentRepo, 'published'].filter(
    (r, i, a) => r && a.indexOf(r) === i,
  );
  const out = [];

  // ansible-galaxy against content/<repo>/ asks for v3/collections/{ns}/{name}/
  // which 302s to a rh-certified index URL that 404s. Prefer the published
  // plugin index shape that actually returns 200.
  const coll = rest.match(
    /^v3\/collections\/([^/]+)\/([^/]+)(?:\/(.*))?$/,
  );
  if (coll) {
    const ns = coll[1];
    const name = coll[2];
    const tail = coll[3] ? `/${coll[3]}` : '/';
    out.push(
      `/v3/plugin/ansible/content/published/collections/index/${ns}/${name}${tail}`,
      `/api/v3/plugin/ansible/content/published/collections/index/${ns}/${name}${tail}`,
    );
    for (const repo of repos) {
      out.push(
        `/content/${repo}/v3/plugin/ansible/content/published/collections/index/${ns}/${name}${tail}`,
      );
    }
  }

  for (const repo of repos) {
    out.push(
      `/content/${repo}/${rest}`,
      `/v3/plugin/ansible/content/${repo}/${rest}`,
      `/api/v3/plugin/ansible/content/${repo}/${rest}`,
    );
  }
  return out;
}

function parseArtifactName(urlPath) {
  const m = urlPath.match(/\/collections\/artifacts\/([^/?#]+)/);
  return m ? m[1] : null;
}

function parseCollectionFromContentPath(urlPath) {
  // Artifact downloads are not collection metadata — check first so we never
  // treat `/collections/artifacts/<file>.tar.gz` as ns=artifacts, name=<file>.
  if (parseArtifactName(urlPath)) return null;

  // PAH / galaxy-proxy shapes:
  //   .../collections/index/{ns}/{name}/...
  //   .../v3/collections/{ns}/{name}/...   (ansible-galaxy against content/<repo>/)
  //   .../collections/{ns}/{name}/versions/...
  const patterns = [
    /\/collections\/index\/([^/]+)\/([^/]+)(?:\/|$)/,
    /\/v3\/collections\/([^/]+)\/([^/]+)(?:\/|$)/,
    /\/collections\/([^/]+)\/([^/]+)(?:\/(?:versions|docs)\/|$)/,
  ];
  for (const re of patterns) {
    const m = urlPath.match(re);
    if (m) return { namespace: m[1], name: m[2] };
  }
  return null;
}

function parseNsNameFromArtifact(filename) {
  // ansible-posix-2.2.2.tar.gz
  const m = String(filename).match(
    /^([^-]+)-(.+)-(\d+\.\d+\.\d+.*?)\.tar\.gz$/i,
  );
  if (!m) return null;
  return { namespace: m[1], name: m[2], version: m[3] };
}

export function registerHubRoutes(app, { store, remotes, cache, env }) {
  const publicBase = store.publicBase;
  const upstreamBases = [
    ...new Set(remotes.map(r => r.base.replace(/\/$/, ''))),
    'https://galaxy.ansible.com',
    'https://console.redhat.com',
    'https://cloud.redhat.com',
  ];

  function rewrite(body, req) {
    const host = req?.headers?.host;
    const proto = String(req?.headers?.['x-forwarded-proto'] || 'http').split(',')[0].trim() || 'http';
    const requestBase = host ? `${proto}://${host}` : publicBase;
    return rewritePayload(body, {
      publicBase: requestBase,
      upstreamBases,
      absolute: true,
    });
  }

  // ── Search (cache only; optional on-demand resolve when ns+name given) ──
  app.get(
    '/api/galaxy/v3/plugin/ansible/search/collection-versions/',
    async (req, reply) => {
      if (!store.requireAuth(req, reply)) return;

      const namespace = req.query.namespace || req.query['namespace__iexact'];
      const name = req.query.name || req.query['name__iexact'];
      const version = req.query.version;

      if (namespace && name) {
        const { entry, authErrors } = await resolveCollection({
          remotes,
          cache,
          namespace: String(namespace),
          name: String(name),
          version: version ? String(version) : undefined,
          log: app.log,
        });
        if (!entry && authErrors?.length && !cache.list().length) {
          // fall through to empty list; auth already logged
        }
        void entry;
      }

      let rows = cache.list();
      if (namespace) {
        rows = rows.filter(
          c => c.namespace.toLowerCase() === String(namespace).toLowerCase(),
        );
      }
      if (name) {
        rows = rows.filter(
          c => c.name.toLowerCase() === String(name).toLowerCase(),
        );
      }
      // repository_name is accepted for PAH sync compatibility; learned cache is shared.

      const limit = Math.min(Number(req.query.limit || 100), 100);
      const offset = Number(req.query.offset || 0);
      const page = rows.slice(offset, offset + limit);

      const data = page.map(c => ({
        collection_version: {
          namespace: c.namespace,
          name: c.name,
          version: c.version,
          description: c.description,
          pulp_href: `/api/galaxy/pulp/api/v3/content/ansible/collection_versions/${encodeURIComponent(`${c.namespace}-${c.name}-${c.version}`)}/`,
        },
        is_highest: true,
        repository: { name: c.contentRepo || 'community' },
      }));

      return {
        meta: { count: rows.length },
        links: {},
        data,
      };
    },
  );

  // ── Pulp repositories (configured PAH names) ──
  app.get('/api/galaxy/pulp/api/v3/repositories', async (req, reply) => {
    if (!store.requireAuth(req, reply)) return;
    const names = getPahRepositoryNames(env);
    let results = names.map((name, i) => ({
      name,
      pulp_href: `/api/galaxy/pulp/api/v3/repositories/${i + 1}/`,
    }));
    if (req.query.name) {
      results = results.filter(r => r.name === String(req.query.name));
    }
    return {
      count: results.length,
      next: null,
      previous: null,
      results,
    };
  });

  // pulp detail stub for docs_blob fetches — return minimal JSON
  app.get(
    '/api/galaxy/pulp/api/v3/content/ansible/collection_versions/:id',
    async (req, reply) => {
      if (!store.requireAuth(req, reply)) return;
      return {
        pulp_href: req.url.split('?')[0],
        authors: [],
        docs_blob: {},
      };
    },
  );

  async function proxyToRemote(remote, upstreamPath, req, reply) {
    const qs = req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : '';
    const pathWithQs = `${upstreamPath}${qs}`;
    const base = remote.base.replace(/\/$/, '');
    const url = `${base}${pathWithQs.startsWith('/') ? pathWithQs : `/${pathWithQs}`}`;
    try {
      // Follow redirects for artifacts (Galaxy/Hub 302 → pulp content / S3).
      const auth =
        typeof remote.getAuthHeaders === 'function'
          ? await remote.getAuthHeaders()
          : remote.token
            ? { Authorization: `Token ${remote.token}` }
            : {};
      // Artifacts: always Accept */* — Hub 302→S3; JSON Accept is for metadata only.
      const isArtifact = Boolean(parseArtifactName(upstreamPath));
      const res = await fetch(url, {
        method: optsMethod(req),
        headers: {
          Accept: isArtifact ? '*/*' : req.headers.accept || '*/*',
          ...auth,
        },
        redirect: 'follow',
      });

      const ctype = res.headers.get('content-type') || '';
      // HEAD responses have no body — do not call res.json() (empty → SyntaxError).
      if (req.method === 'HEAD') {
        if (ctype) reply.header('content-type', ctype);
        reply.code(res.status).send();
        return;
      }
      if (!isArtifact && ctype.includes('application/json')) {
        const body = await res.json();
        reply.code(res.status).send(rewrite(body, req));
        return;
      }

      const buf = Buffer.from(await res.arrayBuffer());
      const artName = parseArtifactName(upstreamPath);
      reply.type(ctype.includes('json') ? 'application/octet-stream' : ctype || 'application/octet-stream');
      if (artName) {
        reply.header(
          'content-disposition',
          `attachment; filename="${artName}"`,
        );
      } else {
        const cd = res.headers.get('content-disposition');
        if (cd) reply.header('content-disposition', cd);
      }
      return reply.code(res.status).send(buf);
    } catch (err) {
      app.log.error(
        { err, upstreamPath, remoteId: remote.id },
        'aap-mock hub proxy failed',
      );
      if (!reply.sent) {
        reply.code(502).send({ detail: `aap-mock upstream error: ${err.message}` });
      }
    }
  }

  /** Hub (and galaxy) artifact tarball paths — prefer published/ for console Hub. */
  function artifactUpstreamPaths(remote, artName) {
    if (remote.kind === 'hub') {
      return [
        `/v3/plugin/ansible/content/published/collections/artifacts/${artName}`,
        `/api/v3/plugin/ansible/content/published/collections/artifacts/${artName}`,
        `/v3/plugin/ansible/content/${remote.contentRepo}/collections/artifacts/${artName}`,
      ];
    }
    return [
      `/api/v3/plugin/ansible/content/${upstreamContentRepo(remote)}/collections/artifacts/${artName}`,
    ];
  }

  async function proxyArtifact(remote, artName, req, reply) {
    const paths = artifactUpstreamPaths(remote, artName);
    let lastErr = null;
    for (const c of paths) {
      try {
        await proxyToRemote(remote, c, req, reply);
        if (reply.sent) return true;
      } catch (err) {
        lastErr = err;
        app.log.warn(
          { err, upstreamPath: c },
          'aap-mock artifact proxy attempt failed',
        );
      }
    }
    if (!reply.sent) {
      reply.code(502).send({
        detail: `aap-mock: artifact download failed${lastErr ? `: ${lastErr.message}` : ''}`,
      });
    }
    return false;
  }

  function optsMethod(req) {
    return req.method === 'HEAD' ? 'HEAD' : 'GET';
  }

  async function ensureResolvedForPath(urlPath, req, reply) {
    const coll = parseCollectionFromContentPath(urlPath);
    if (coll) {
      const { entry } = await resolveCollection({
        remotes,
        cache,
        namespace: coll.namespace,
        name: coll.name,
        log: app.log,
      });
      return entry;
    }
    const art = parseArtifactName(urlPath);
    if (art) {
      const parsed = parseNsNameFromArtifact(art);
      if (parsed) {
        const { entry } = await resolveCollection({
          remotes,
          cache,
          namespace: parsed.namespace,
          name: parsed.name,
          version: parsed.version,
          log: app.log,
        });
        return entry;
      }
    }
    return null;
  }

  // ── Content plane (ansible-galaxy / APME) ──
  app.route({
    method: ['GET', 'HEAD'],
    url: '/api/galaxy/content/*',
    handler: async (req, reply) => {
      if (!store.requireAuth(req, reply)) return;
      const urlPath = req.url.split('?')[0];

      // Artifact tarballs: resolve collection then fetch published/ (Hub 302→S3).
      const artName = parseArtifactName(urlPath);
      if (artName) {
        const entry = await ensureResolvedForPath(urlPath, req, reply);
        const remote =
          (entry && remotes.find(r => r.id === entry.remoteId)) ||
          remotes.find(r => r.kind === 'hub' && r.token) ||
          remotes.find(r => r.kind === 'galaxy');
        await proxyArtifact(remote, artName, req, reply);
        return;
      }

      const entry = await ensureResolvedForPath(urlPath, req, reply);
      if (!entry) {
        // Still try galaxy published for bare prefix probes
        const remote =
          remotes.find(r => r.id === 'galaxy') || remotes[remotes.length - 1];
        const candidates = hubPathCandidates(remote, urlPath);
        for (const up of candidates) {
          const probe = await upstreamFetch(remote, up).catch(() => null);
          if (probe && probe.ok) {
            // re-fetch via proxyToRemote
            await proxyToRemote(remote, up, req, reply);
            return;
          }
        }
        reply.code(404).send({
          detail: `aap-mock: collection not found via cascade (certified→validated→galaxy) for ${urlPath}`,
        });
        return;
      }

      const remote =
        remotes.find(r => r.id === entry.remoteId) ||
        remotes.find(r => r.kind === 'galaxy');
      // Rewrite PAH content repo segment to the remote's content repo
      const adjusted = urlPath.replace(
        /^\/api\/galaxy\/content\/[^/]+\//,
        `/api/galaxy/content/${entry.contentRepo}/`,
      );
      const candidates = hubPathCandidates(remote, adjusted);
      // Prefer real 200/OK over bare redirects — Hub often 302s to a 404 index.
      let redirectFallback = null;
      for (const up of candidates) {
        const probe = await upstreamFetch(remote, up).catch(() => null);
        if (!probe) continue;
        // Drain unused probe bodies so sockets can be reused.
        void probe.arrayBuffer().catch(() => {});
        if (probe.ok) {
          await proxyToRemote(remote, up, req, reply);
          return;
        }
        if (
          !redirectFallback &&
          (probe.status === 302 || probe.status === 301)
        ) {
          redirectFallback = up;
        }
      }
      if (redirectFallback) {
        await proxyToRemote(remote, redirectFallback, req, reply);
        return;
      }
      reply.code(502).send({
        detail: `aap-mock: upstream content miss for ${entry.namespace}.${entry.name} on ${entry.remoteId}`,
      });
    },
  });

  // ── Generic /api/galaxy/v3 and /api/galaxy/pulp reverse-proxy (post-rewrite) ──
  app.route({
    method: ['GET', 'HEAD'],
    url: '/api/galaxy/v3/*',
    handler: async (req, reply) => {
      if (!store.requireAuth(req, reply)) return;
      const urlPath = req.url.split('?')[0];

      // Artifact downloads first — never mis-parse as collection metadata.
      const artName = parseArtifactName(urlPath);
      if (artName) {
        const parsed = parseNsNameFromArtifact(artName);
        let remote =
          remotes.find(r => r.kind === 'hub' && r.token) ||
          remotes.find(r => r.kind === 'galaxy');
        if (parsed) {
          const entry =
            cache.get(parsed.namespace, parsed.name, parsed.version) ||
            (
              await resolveCollection({
                remotes,
                cache,
                namespace: parsed.namespace,
                name: parsed.name,
                version: parsed.version,
                log: app.log,
              })
            ).entry;
          if (entry) {
            remote = remotes.find(r => r.id === entry.remoteId) || remote;
          }
        }
        await proxyArtifact(remote, artName, req, reply);
        return;
      }

      // Prefer cached remote if path references a known collection; else galaxy
      const coll = parseCollectionFromContentPath(urlPath);
      let remote = remotes.find(r => r.kind === 'galaxy');
      if (coll) {
        const entry =
          cache.get(coll.namespace, coll.name, coll.version) ||
          (
            await resolveCollection({
              remotes,
              cache,
              namespace: coll.namespace,
              name: coll.name,
              version: coll.version,
              log: app.log,
            })
          ).entry;
        if (entry) {
          remote = remotes.find(r => r.id === entry.remoteId) || remote;
        }
      }
      const up = galaxyPathFromPah(urlPath);
      if (!up) {
        reply.code(404).send({ detail: 'aap-mock: bad galaxy path' });
        return;
      }
      // Hub remotes don't use /api/v3 under galaxy.ansible.com — map plugin content differently
      if (remote.kind === 'hub') {
        const rest = urlPath.replace(/^\/api\/galaxy\/v3\//, '');
        // Artifacts on console Hub are under published/, even for certified hits.
        const repos = [remote.contentRepo, 'published'].filter(
          (r, i, a) => r && a.indexOf(r) === i,
        );
        const candidates = [];
        for (const repo of repos) {
          const repoRest = rest.replace(
            /plugin\/ansible\/content\/[^/]+\//,
            `plugin/ansible/content/${repo}/`,
          );
          candidates.push(
            `/v3/${repoRest}`,
            `/api/v3/${repoRest}`,
            `/content/${repo}/v3/${repoRest}`,
          );
        }
        candidates.push(`/v3/${rest}`, `/api/v3/${rest}`);
        let redirectFallback = null;
        for (const c of candidates) {
          const probe = await upstreamFetch(remote, c).catch(() => null);
          if (!probe) continue;
          // Drain unused probe bodies so sockets can be reused.
          void probe.arrayBuffer().catch(() => {});
          if (probe.ok) {
            await proxyToRemote(remote, c, req, reply);
            return;
          }
          if (
            !redirectFallback &&
            (probe.status === 302 || probe.status === 301)
          ) {
            redirectFallback = c;
          }
        }
        if (redirectFallback) {
          await proxyToRemote(remote, redirectFallback, req, reply);
          return;
        }
        reply.code(404).send({ detail: 'aap-mock: hub v3 path not found' });
        return;
      }
      await proxyToRemote(remote, up, req, reply);
    },
  });
}
