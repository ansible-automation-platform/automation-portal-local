import Fastify from 'fastify';
import formbody from '@fastify/formbody';
import { createStore } from './store.js';
import { createHubCache } from './hubCache.js';
import { getRemotes } from './hubRemotes.js';
import {
  attachHubAuth,
  createHubAccessTokenProvider,
} from './hubAuth.js';
import { registerHubRoutes } from './hubProxy.js';

const env = process.env;
const store = createStore(env);
const hubCache = createHubCache();
const hubTokenProvider = createHubAccessTokenProvider({
  refreshToken: env.AAP_MOCK_HUB_TOKEN,
  authUrl: env.AAP_MOCK_HUB_AUTH_URL,
  clientId: env.AAP_MOCK_HUB_AUTH_CLIENT_ID,
  log: console,
});
const hubRemotes = attachHubAuth(getRemotes(env), hubTokenProvider);
const port = Number(env.PORT || 8099);
const clientId = env.OAUTH_CLIENT_ID || 'portal-local-mock';
const clientSecret = env.OAUTH_CLIENT_SECRET || 'portal-local-mock-secret';

const app = Fastify({ logger: true });
await app.register(formbody);

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function loginPage({ error, query, username, password }) {
  const qs = new URLSearchParams(query).toString();
  const err = error
    ? `<p style="color:#c9190b;margin:0 0 1rem">${escapeHtml(error)}</p>`
    : '';
  const userVal = escapeHtml(username || 'user');
  const passVal = escapeHtml(password || 'password');
  // Auto-submit only on a clean login prompt (not after a failed attempt).
  const autoBlock = error
    ? ''
    : `
    <p class="auto" id="auto-row" aria-live="polite">
      Signing in automatically in <strong id="countdown">3</strong>s…
      <button type="button" id="cancel-auto" class="cancel">Cancel</button>
    </p>
    <script>
    (function () {
      var seconds = 3;
      var cancelled = false;
      var form = document.getElementById('login-form');
      var countdown = document.getElementById('countdown');
      var row = document.getElementById('auto-row');
      var cancelBtn = document.getElementById('cancel-auto');
      function cancelAuto() {
        if (cancelled) return;
        cancelled = true;
        clearInterval(timer);
        row.innerHTML = 'Auto sign-in cancelled.';
      }
      var timer = setInterval(function () {
        if (cancelled) return;
        seconds -= 1;
        if (seconds <= 0) {
          clearInterval(timer);
          if (typeof form.requestSubmit === 'function') form.requestSubmit();
          else form.submit();
          return;
        }
        countdown.textContent = String(seconds);
      }, 1000);
      cancelBtn.addEventListener('click', cancelAuto);
      ['username', 'password'].forEach(function (id) {
        var el = document.getElementById(id);
        el.addEventListener('input', cancelAuto);
        el.addEventListener('focus', cancelAuto);
      });
    })();
    </script>`;
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Almost like AAP — Sign in</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center;
      background: linear-gradient(160deg, #1b1b1b 0%, #3d0000 55%, #151515 100%); color: #f5f5f5; }
    .card { width: min(380px, 92vw); background: #222; border: 1px solid #444;
      border-radius: 8px; padding: 1.75rem; box-shadow: 0 12px 40px rgba(0,0,0,.45); }
    h1 { margin: 0 0 .25rem; font-size: 1.35rem; letter-spacing: .02em; }
    .sub { margin: 0 0 1.25rem; color: #bbb; font-size: .9rem; }
    label { display: block; font-size: .8rem; margin: .75rem 0 .35rem; color: #ddd; }
    input { width: 100%; box-sizing: border-box; padding: .55rem .65rem; border-radius: 4px;
      border: 1px solid #555; background: #111; color: #fff; }
    button[type="submit"] { margin-top: 1.25rem; width: 100%; padding: .65rem; border: 0; border-radius: 4px;
      background: #ee0000; color: #fff; font-weight: 600; cursor: pointer; }
    button[type="submit"]:hover { background: #c00; }
    .auto { margin: 1rem 0 0; font-size: .8rem; color: #bbb; display: flex; flex-wrap: wrap;
      align-items: center; gap: .5rem .75rem; }
    .auto strong { color: #fff; font-variant-numeric: tabular-nums; }
    button.cancel { margin: 0; width: auto; padding: .25rem .65rem; border: 1px solid #666;
      border-radius: 4px; background: transparent; color: #ddd; font-weight: 500; cursor: pointer; font-size: .8rem; }
    button.cancel:hover { border-color: #aaa; color: #fff; }
    .hint { margin-top: 1rem; font-size: .75rem; color: #888; }
    code { color: #f0c; }
  </style>
</head>
<body>
  <form id="login-form" class="card" method="post" action="/o/authorize/?${qs}">
    <h1>Almost like AAP</h1>
    <p class="sub">Local mock for automation-portal-local. Not a real Controller.</p>
    ${err}
    <label for="username">Username</label>
    <input id="username" name="username" autocomplete="username" required value="${userVal}"/>
    <label for="password">Password</label>
    <input id="password" name="password" type="password" autocomplete="current-password" required value="${passVal}"/>
    <button type="submit">Sign in</button>
    ${autoBlock}
    <p class="hint">Default credentials: <code>${userVal}</code> / <code>${passVal}</code></p>
  </form>
</body>
</html>`;
}

app.get('/health', async () => ({ status: 'ok', service: 'aap-mock' }));

// ── OAuth ─────────────────────────────────────────────────────────────
app.get('/o/authorize/', async (req, reply) => {
  reply.type('text/html').send(
    loginPage({
      query: req.query,
      username: store.username,
      password: store.password,
    }),
  );
});

app.post('/o/authorize/', async (req, reply) => {
  const body = req.body || {};
  const q = req.query || {};
  if (body.username !== store.username || body.password !== store.password) {
    reply
      .type('text/html')
      .code(401)
      .send(
        loginPage({
          error: 'Invalid username or password.',
          query: q,
          username: store.username,
          password: store.password,
        }),
      );
    return;
  }
  const redirectUri = q.redirect_uri;
  if (!redirectUri) {
    reply.code(400).send({ error: 'missing redirect_uri' });
    return;
  }
  const code = store.issueCode(body.username);
  const dest = new URL(redirectUri);
  dest.searchParams.set('code', code);
  if (q.state) dest.searchParams.set('state', q.state);
  if (q.scope) dest.searchParams.set('scope', q.scope);
  return reply.redirect(dest.toString());
});

app.post('/o/token/', async (req, reply) => {
  const body = req.body || {};
  // Accept form or JSON
  const grant = body.grant_type || 'authorization_code';
  const id = body.client_id || clientId;
  const secret = body.client_secret || clientSecret;
  if (id !== clientId || secret !== clientSecret) {
    // Be lenient if Basic auth was used instead
    const auth = req.headers.authorization || '';
    if (!auth.startsWith('Basic ')) {
      reply.code(401).send({ error: 'invalid_client' });
      return;
    }
  }
  if (grant === 'client_credentials') {
    return store.issueToken(store.username);
  }
  if (grant === 'authorization_code') {
    const userName = store.consumeCode(body.code);
    if (!userName) {
      reply.code(400).send({ error: 'invalid_grant' });
      return;
    }
    return store.issueToken(userName);
  }
  if (grant === 'refresh_token') {
    const next = store.refreshAccessToken(body.refresh_token);
    if (!next) {
      reply.code(400).send({ error: 'invalid_grant' });
      return;
    }
    return next;
  }
  // password grant (some clients)
  if (grant === 'password') {
    if (body.username === store.username && body.password === store.password) {
      return store.issueToken(store.username);
    }
    reply.code(400).send({ error: 'invalid_grant' });
    return;
  }
  reply.code(400).send({ error: 'unsupported_grant_type' });
});

app.post('/o/revoke_token/', async (_req, reply) => {
  reply.code(200).send({});
});

// ── Gateway ───────────────────────────────────────────────────────────
app.get('/api/gateway/v1/me/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  return store.page([store.user], req);
});

app.get('/api/gateway/v1/organizations/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  let orgs = [store.org];
  if (req.query.name__iexact) {
    orgs = orgs.filter(
      o => o.name.toLowerCase() === String(req.query.name__iexact).toLowerCase(),
    );
  }
  if (req.query.or__name__iexact) {
    const names = []
      .concat(req.query.or__name__iexact)
      .map(n => String(n).toLowerCase());
    orgs = orgs.filter(o => names.includes(o.name.toLowerCase()));
  }
  return store.page(orgs, req);
});

app.get('/api/gateway/v1/organizations/:id/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  if (Number(req.params.id) !== store.org.id) {
    reply.code(404).send({ detail: 'Not found.' });
    return;
  }
  return store.org;
});

app.get('/api/gateway/v1/organizations/:id/users/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  return store.page([store.user], req);
});

app.get('/api/gateway/v1/organizations/:id/teams/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  return store.page([store.team], req);
});

app.get('/api/gateway/v1/teams/:id/users/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  return store.page([store.user], req);
});

app.get('/api/gateway/v1/users/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  let users = [store.user];
  if (req.query.is_superuser === 'true') {
    users = users.filter(u => u.is_superuser);
  }
  return store.page(users, req);
});

app.get('/api/gateway/v1/users/:id/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  if (Number(req.params.id) !== store.user.id) {
    reply.code(404).send({ detail: 'Not found.' });
    return;
  }
  // Shape expected by AAPClient.getUserInfoById
  return {
    ...store.user,
    url: `${store.publicBase}/api/gateway/v1/users/${store.user.id}/`,
    summary_fields: {
      organizations: [{ id: store.org.id, name: store.org.name }],
    },
  };
});

app.get('/api/gateway/v1/users/:id/teams/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  return store.page([store.team], req);
});

app.get('/api/gateway/v1/users/:id/organizations/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  return store.page([store.org], req);
});

app.get('/api/gateway/v1/role_user_assignments/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  return store.page(
    [
      {
        id: 1,
        user: store.user.id,
        object_id: String(store.org.id),
        summary_fields: {
          role_definition: { name: 'Organization Admin' },
          user: {
            id: store.user.id,
            username: store.user.username,
          },
          object: {
            id: store.org.id,
            name: store.org.name,
          },
        },
      },
    ],
    req,
  );
});

app.get('/api/gateway/v1/services/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  const results = [
    {
      id: 1,
      name: 'controller',
      api_slug: 'controller',
      status: 'ready',
      // Controllers often resolve relative to gateway host
      href: `${store.publicBase}/api/controller/`,
    },
  ];
  if (req.query.api_slug) {
    return store.page(
      results.filter(s => s.api_slug === req.query.api_slug),
      req,
    );
  }
  return store.page(results, req);
});

// ── Controller helpers ────────────────────────────────────────────────
function listResource(req, reply, listFn) {
  if (!store.requireAuth(req, reply)) return;
  const filtered = store.filterByQuery(listFn(), req);
  return store.page(filtered, req);
}

app.get('/api/controller/v2/projects/', async (req, reply) =>
  listResource(req, reply, () => store.listProjects()),
);
app.post('/api/controller/v2/projects/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  reply.code(201).send(store.createProject(req.body || {}));
});
app.get('/api/controller/v2/projects/:id/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  const p = store.listProjects().find(x => x.id === Number(req.params.id));
  if (!p) {
    reply.code(404).send({ detail: 'Not found.' });
    return;
  }
  return p;
});
app.delete('/api/controller/v2/projects/:id/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  reply.code(204).send();
});

app.get('/api/controller/v2/job_templates/', async (req, reply) =>
  listResource(req, reply, () => store.listJobTemplates()),
);
app.post('/api/controller/v2/job_templates/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  reply.code(201).send(store.createJobTemplate(req.body || {}));
});
app.get('/api/controller/v2/job_templates/:id/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  const t = store.getJobTemplate(req.params.id);
  if (!t) {
    reply.code(404).send({ detail: 'Not found.' });
    return;
  }
  return t;
});
app.post('/api/controller/v2/job_templates/:id/launch/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  const job = store.launchJobTemplate(req.params.id);
  if (!job) {
    reply.code(404).send({ detail: 'Not found.' });
    return;
  }
  reply.code(201).send(job);
});

app.get('/api/controller/v2/jobs/:id/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  const j = store.getJob(req.params.id);
  if (!j) {
    reply.code(404).send({ detail: 'Not found.' });
    return;
  }
  return j;
});
app.get('/api/controller/v2/jobs/:id/stdout/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  const text = store.jobStdout(req.params.id);
  if (text == null) {
    reply.code(404).send({ detail: 'Not found.' });
    return;
  }
  if (req.query.format === 'txt' || req.query.format === 'ansi') {
    reply.type('text/plain').send(text);
    return;
  }
  return { content: text };
});
app.get('/api/controller/v2/jobs/:id/job_events/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  return store.page([], req);
});
app.post('/api/controller/v2/jobs/:id/cancel/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  const j = store.cancelJob(req.params.id);
  if (!j) {
    reply.code(404).send({ detail: 'Not found.' });
    return;
  }
  return j;
});

app.get('/api/controller/v2/inventories/', async (req, reply) =>
  listResource(req, reply, () => store.listInventories()),
);
app.get('/api/controller/v2/execution_environments/', async (req, reply) =>
  listResource(req, reply, () => store.listEEs()),
);
app.post('/api/controller/v2/execution_environments/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  reply.code(201).send(store.createEE(req.body || {}));
});
app.get('/api/controller/v2/execution_environments/:id/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  const e = store.listEEs().find(x => x.id === Number(req.params.id));
  if (!e) {
    reply.code(404).send({ detail: 'Not found.' });
    return;
  }
  return e;
});
app.delete('/api/controller/v2/execution_environments/:id/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  reply.code(204).send();
});

// Generic list for scaffolder autocomplete
app.get('/api/controller/v2/:resource/', async (req, reply) => {
  if (!store.requireAuth(req, reply)) return;
  const map = {
    organizations: () => [store.org],
    inventories: () => store.listInventories(),
    projects: () => store.listProjects(),
    job_templates: () => store.listJobTemplates(),
    execution_environments: () => store.listEEs(),
    credentials: () => [],
    teams: () => [store.team],
    users: () => [store.user],
  };
  const fn = map[req.params.resource];
  if (!fn) {
    reply.code(501).send({
      detail: `aap-mock: unsupported controller resource '${req.params.resource}'`,
    });
    return;
  }
  return store.page(store.filterByQuery(fn(), req), req);
});

// ── Galaxy / Hub (on-demand cascade + learned cache) ─────────────────
await registerHubRoutes(app, {
  store,
  remotes: hubRemotes,
  cache: hubCache,
  env,
});

// Fallback
app.setNotFoundHandler(async (req, reply) => {
  reply.code(501).send({
    detail: `aap-mock: unsupported path ${req.method} ${req.url}`,
  });
});

await app.listen({ port, host: '0.0.0.0' });
app.log.info(
  `Almost like AAP listening on :${port} (login ${store.username} / ****); hub cascade certified→validated→galaxy (cache size ${hubCache.size()})`,
);
