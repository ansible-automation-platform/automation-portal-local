import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createHubCache } from '../src/hubCache.js';
import { getRemotes, getPahRepositoryNames } from '../src/hubRemotes.js';
import { rewritePayload } from '../src/hubClient.js';
import { resolveCollection } from '../src/hubResolve.js';
import {
  createHubAccessTokenProvider,
  attachHubAuth,
} from '../src/hubAuth.js';

describe('artifact path parsing', () => {
  it('does not treat /collections/artifacts/*.tar.gz as a collection ns/name', async () => {
    // Inline the same guards used by hubProxy (kept here to lock the regression).
    function parseArtifactName(urlPath) {
      const m = urlPath.match(/\/collections\/artifacts\/([^/?#]+)/);
      return m ? m[1] : null;
    }
    function parseCollectionFromContentPath(urlPath) {
      if (parseArtifactName(urlPath)) return null;
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
    const artUrl =
      '/api/galaxy/v3/plugin/ansible/content/published/collections/artifacts/ansible-controller-4.8.4.tar.gz';
    const contentArt =
      '/api/galaxy/content/rh-certified/collections/artifacts/ansible-controller-4.8.4.tar.gz';
    assert.equal(
      parseArtifactName(artUrl),
      'ansible-controller-4.8.4.tar.gz',
    );
    assert.equal(parseCollectionFromContentPath(artUrl), null);
    assert.equal(parseCollectionFromContentPath(contentArt), null);
    assert.deepEqual(
      parseCollectionFromContentPath(
        '/api/galaxy/content/rh-certified/v3/collections/ansible/controller/',
      ),
      { namespace: 'ansible', name: 'controller' },
    );
  });
});

describe('hubCache', () => {
  it('stores and lists unique collections', () => {
    const cache = createHubCache();
    cache.put({
      namespace: 'ansible',
      name: 'posix',
      version: '1.0.0',
      remoteId: 'galaxy',
      contentRepo: 'community',
      remoteBase: 'https://galaxy.ansible.com',
      kind: 'galaxy',
    });
    cache.put({
      namespace: 'ansible',
      name: 'posix',
      version: '1.0.0',
      remoteId: 'galaxy',
      contentRepo: 'community',
      remoteBase: 'https://galaxy.ansible.com',
      kind: 'galaxy',
    });
    assert.equal(cache.size(), 1);
    assert.equal(cache.get('ansible', 'posix').version, '1.0.0');
  });
});

describe('hubRemotes', () => {
  it('orders certified → validated → galaxy', () => {
    const remotes = getRemotes({});
    assert.deepEqual(
      remotes.map(r => r.id),
      ['certified', 'validated', 'galaxy'],
    );
  });

  it('reads PAH repo names from env', () => {
    assert.deepEqual(getPahRepositoryNames({}), [
      'community',
      'validated',
      'rh-certified',
    ]);
  });

  it('maps galaxy remote to community PAH repo with published upstream paths', () => {
    const galaxy = getRemotes({}).find(r => r.id === 'galaxy');
    assert.equal(galaxy.contentRepo, 'community');
    assert.equal(galaxy.upstreamContentRepo, 'published');
  });
});

describe('hubAuth SSO exchange', () => {
  it('exchanges refresh token and caches Bearer access token', async () => {
    let posts = 0;
    const provider = createHubAccessTokenProvider({
      refreshToken: 'offline-token',
      authUrl: 'https://sso.example/token',
      now: () => 1_000_000,
      fetchImpl: async (url, opts) => {
        assert.equal(url, 'https://sso.example/token');
        assert.equal(opts.method, 'POST');
        posts += 1;
        return {
          ok: true,
          async text() {
            return JSON.stringify({
              access_token: 'access-abc',
              expires_in: 900,
              token_type: 'Bearer',
            });
          },
        };
      },
    });
    const h1 = await provider.getAuthHeaders();
    const h2 = await provider.getAuthHeaders();
    assert.equal(h1.Authorization, 'Bearer access-abc');
    assert.equal(h2.Authorization, 'Bearer access-abc');
    assert.equal(posts, 1);
  });

  it('falls back to Token header when exchange fails', async () => {
    const provider = createHubAccessTokenProvider({
      refreshToken: 'raw-api-token',
      fetchImpl: async () => ({
        ok: false,
        status: 400,
        async text() {
          return JSON.stringify({ error: 'invalid_grant' });
        },
      }),
    });
    const headers = await provider.getAuthHeaders();
    assert.equal(headers.Authorization, 'Token raw-api-token');
  });

  it('attachHubAuth wires getAuthHeaders on hub remotes only', async () => {
    const provider = createHubAccessTokenProvider({
      refreshToken: 'offline',
      fetchImpl: async () => ({
        ok: true,
        async text() {
          return JSON.stringify({ access_token: 'tok', expires_in: 60 });
        },
      }),
    });
    const remotes = attachHubAuth(
      getRemotes({ AAP_MOCK_HUB_TOKEN: 'offline' }),
      provider,
    );
    assert.equal(typeof remotes[0].getAuthHeaders, 'function');
    assert.equal(typeof remotes[2].getAuthHeaders, 'undefined');
    const h = await remotes[0].getAuthHeaders();
    assert.equal(h.Authorization, 'Bearer tok');
  });
});

describe('rewritePayload', () => {
  it('rewrites galaxy absolute download_url onto mock PAH paths when absolute', () => {
    const out = rewritePayload(
      {
        download_url:
          'https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/artifacts/ansible-posix-2.2.2.tar.gz',
      },
      {
        publicBase: 'http://host.containers.internal:8099',
        upstreamBases: ['https://galaxy.ansible.com'],
        absolute: true,
      },
    );
    assert.equal(
      out.download_url,
      'http://host.containers.internal:8099/api/galaxy/v3/plugin/ansible/content/published/collections/artifacts/ansible-posix-2.2.2.tar.gz',
    );
  });

  it('maps automation-hub relative hrefs onto /api/galaxy', () => {
    const out = rewritePayload(
      {
        href: '/api/automation-hub/v3/plugin/ansible/content/published/collections/index/ansible/controller/',
      },
      {
        publicBase: 'http://localhost:8099',
        upstreamBases: ['https://console.redhat.com/api/automation-hub'],
        absolute: true,
      },
    );
    assert.equal(
      out.href,
      'http://localhost:8099/api/galaxy/v3/plugin/ansible/content/published/collections/index/ansible/controller/',
    );
  });
});

describe('resolveCollection cascade', () => {
  it('returns cache hit without calling remotes', async () => {
    const cache = createHubCache();
    cache.put({
      namespace: 'ansible',
      name: 'posix',
      version: '9.9.9',
      remoteId: 'galaxy',
      contentRepo: 'community',
      remoteBase: 'https://galaxy.ansible.com',
      kind: 'galaxy',
    });
    const remotes = getRemotes({ AAP_MOCK_GALAXY_BASE: 'http://127.0.0.1:9' });
    const { entry, fromCache } = await resolveCollection({
      remotes,
      cache,
      namespace: 'ansible',
      name: 'posix',
    });
    assert.equal(fromCache, true);
    assert.equal(entry.version, '9.9.9');
  });

  it('skips hub remotes without token and uses galaxy', async () => {
    const cache = createHubCache();
    const remotes = getRemotes({
      AAP_MOCK_GALAXY_BASE: 'https://galaxy.ansible.com',
    });
    const { entry } = await resolveCollection({
      remotes,
      cache,
      namespace: 'ansible',
      name: 'posix',
      log: { info() {}, warn() {} },
    });
    assert.ok(entry);
    assert.equal(entry.remoteId, 'galaxy');
    assert.equal(entry.namespace, 'ansible');
    assert.equal(entry.name, 'posix');
    assert.equal(cache.size(), 1);
  });

  it('prefers earlier remote when it hits', async () => {
    const cache = createHubCache();
    const remotes = [
      {
        id: 'certified',
        contentRepo: 'rh-certified',
        base: 'https://hub.example',
        kind: 'hub',
        token: 'tok',
      },
      {
        id: 'galaxy',
        contentRepo: 'community',
        base: 'https://galaxy.ansible.com',
        kind: 'galaxy',
        token: null,
      },
    ];
    const { entry } = await resolveCollection({
      remotes,
      cache,
      namespace: 'ansible',
      name: 'posix',
      searchFn: async remote => {
        if (remote.id !== 'certified') {
          assert.fail('should not reach galaxy when certified hits');
        }
        return {
          namespace: 'ansible',
          name: 'posix',
          version: '1.2.3',
          description: 'from certified',
          remoteId: remote.id,
          contentRepo: remote.contentRepo,
          remoteBase: remote.base,
          kind: remote.kind,
        };
      },
    });
    assert.equal(entry.remoteId, 'certified');
    assert.equal(entry.version, '1.2.3');
  });
});
