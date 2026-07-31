/**
 * In-memory AAP state for portal-local DX.
 */

function nowIso() {
  return new Date().toISOString();
}

export function createStore(env) {
  const username = env.AAP_MOCK_USERNAME || 'user';
  const password = env.AAP_MOCK_PASSWORD || 'password';
  const publicBase = (env.AAP_PUBLIC_URL || 'http://localhost:8099').replace(
    /\/$/,
    '',
  );
  const serviceToken = env.AAP_TOKEN || 'local-mock-token';

  let nextId = 100;
  const allocId = () => ++nextId;

  const org = {
    id: 1,
    name: 'Default',
    description: 'Local mock organization',
    // Required by AAPClient.getOrganizations(true) → org.related.teams / users
    related: {
      users: '/api/gateway/v1/organizations/1/users/',
      teams: '/api/gateway/v1/organizations/1/teams/',
    },
  };

  const user = {
    id: 1,
    username,
    email: `${username}@localhost`,
    first_name: 'Local',
    last_name: 'Developer',
    is_superuser: true,
  };

  const team = {
    id: 1,
    name: 'Admins',
    organization: org.id,
    description: 'Local mock admin team',
    // Required by AAPClient.getTeamsByUserId → summary_fields.organization.name
    summary_fields: {
      organization: {
        id: org.id,
        name: org.name,
      },
    },
    related: {
      users: '/api/gateway/v1/teams/1/users/',
    },
  };

  const inventory = {
    id: 1,
    name: 'Demo Inventory',
    organization: org.id,
  };

  const project = {
    id: 6,
    name: 'Demo Project',
    description: 'Seeded mock project',
    organization: org.id,
    scm_type: 'git',
    scm_url: 'https://github.com/ansible/ansible-lightspeed',
  };

  const jobTemplate = {
    id: 7,
    name: 'Demo Job Template',
    description: 'Seeded mock job template',
    organization: org.id,
    inventory: inventory.id,
    project: project.id,
    playbook: 'site.yml',
  };

  const ee = {
    id: 1,
    name: 'Demo EE',
    description: 'Seeded execution environment',
    organization: org.id,
    image: 'quay.io/ansible/ansible-runner:latest',
  };

  const jobs = new Map();
  const codes = new Map();
  const tokens = new Map();
  const extra = {
    projects: [],
    jobTemplates: [],
    inventories: [],
    ees: [],
  };

  const collections = [
    {
      namespace: 'ansible',
      name: 'posix',
      version: '1.5.4',
      description: 'Mock PAH collection',
    },
  ];

  function page(results, req) {
    const pageNum = Number(req.query.page || 1);
    const pageSize = Number(req.query.page_size || 200);
    const start = (pageNum - 1) * pageSize;
    const slice = results.slice(start, start + pageSize);
    return {
      count: results.length,
      next: start + pageSize < results.length ? `?page=${pageNum + 1}` : null,
      previous: pageNum > 1 ? `?page=${pageNum - 1}` : null,
      results: slice,
    };
  }

  function authHeaderUser(req) {
    const h = req.headers.authorization || '';
    const m = h.match(/^(?:Bearer|Token)\s+(.+)$/i);
    if (!m) return null;
    if (m[1] === serviceToken) return username;
    const tok = tokens.get(m[1]);
    if (!tok || tok.expires < Date.now()) return null;
    return tok.username;
  }

  function requireAuth(req, reply) {
    const u = authHeaderUser(req);
    if (!u) {
      reply
        .code(401)
        .send({ detail: 'Authentication credentials were not provided.' });
      return null;
    }
    return u;
  }

  function scheduleJob(job) {
    setTimeout(() => {
      const j = jobs.get(job.id);
      if (j) j.status = 'running';
    }, 300);
    setTimeout(() => {
      const j = jobs.get(job.id);
      if (j) {
        j.status = 'successful';
        j.finished = nowIso();
      }
    }, 1200);
  }

  const store = {
    username,
    password,
    publicBase,
    serviceToken,
    org,
    user,
    team,
    collections,
    page,
    requireAuth,
    issueCode(userName) {
      const code = `code_${allocId()}_${Math.random().toString(36).slice(2)}`;
      codes.set(code, { username: userName, expires: Date.now() + 5 * 60_000 });
      return code;
    },
    consumeCode(code) {
      const c = codes.get(code);
      codes.delete(code);
      if (!c || c.expires < Date.now()) return null;
      return c.username;
    },
    issueToken(userName) {
      const access_token = `tok_${allocId()}_${Math.random().toString(36).slice(2)}`;
      const refresh_token = `rtok_${allocId()}_${Math.random().toString(36).slice(2)}`;
      const expires = Date.now() + 24 * 60 * 60_000;
      tokens.set(access_token, { username: userName, expires });
      // Backstage calls /api/auth/rhaap/refresh immediately after login;
      // AAP OAuth requires a refresh_token grant against /o/token/.
      tokens.set(refresh_token, {
        username: userName,
        expires: Date.now() + 7 * 24 * 60 * 60_000,
        kind: 'refresh',
      });
      return {
        access_token,
        refresh_token,
        token_type: 'Bearer',
        expires_in: 86400,
        scope: 'read write',
      };
    },
    refreshAccessToken(refreshToken) {
      const tok = tokens.get(refreshToken);
      if (!tok || tok.expires < Date.now()) return null;
      return store.issueToken(tok.username);
    },
    listProjects() {
      return [project, ...extra.projects];
    },
    listJobTemplates() {
      return [jobTemplate, ...extra.jobTemplates];
    },
    listInventories() {
      return [inventory, ...extra.inventories];
    },
    listEEs() {
      return [ee, ...extra.ees];
    },
    getJobTemplate(tid) {
      return store.listJobTemplates().find(t => t.id === Number(tid));
    },
    getJob(jid) {
      return jobs.get(Number(jid));
    },
    createProject(body) {
      const p = {
        id: allocId(),
        name: body.name || 'project',
        description: body.description || '',
        organization: body.organization || org.id,
        scm_type: body.scm_type || 'git',
        scm_url: body.scm_url || '',
        created: nowIso(),
      };
      extra.projects.push(p);
      return p;
    },
    createJobTemplate(body) {
      const t = {
        id: allocId(),
        name: body.name || 'job-template',
        description: body.description || '',
        organization: body.organization || org.id,
        inventory: body.inventory || inventory.id,
        project: body.project || project.id,
        playbook: body.playbook || 'site.yml',
        created: nowIso(),
      };
      extra.jobTemplates.push(t);
      return t;
    },
    createEE(body) {
      const e = {
        id: allocId(),
        name: body.name || 'ee',
        description: body.description || '',
        organization: body.organization || org.id,
        image: body.image || 'quay.io/ansible/ansible-runner:latest',
        created: nowIso(),
      };
      extra.ees.push(e);
      return e;
    },
    launchJobTemplate(tid) {
      const tmpl = store.getJobTemplate(tid);
      if (!tmpl) return null;
      const job = {
        id: allocId(),
        name: tmpl.name,
        status: 'pending',
        job_template: tmpl.id,
        created: nowIso(),
        finished: null,
      };
      jobs.set(job.id, job);
      scheduleJob(job);
      return job;
    },
    jobStdout(jid) {
      const j = jobs.get(Number(jid));
      if (!j) return null;
      return `PLAY [mock] **************************************************************\n\nok: [localhost]\n\nJOB STATUS: ${j.status}\n`;
    },
    cancelJob(jid) {
      const j = jobs.get(Number(jid));
      if (!j) return null;
      j.status = 'canceled';
      j.finished = nowIso();
      return j;
    },
    filterByQuery(list, req, nameField = 'name') {
      let out = [...list];
      if (req.query.name__iexact) {
        out = out.filter(
          x =>
            String(x[nameField]).toLowerCase() ===
            String(req.query.name__iexact).toLowerCase(),
        );
      } else if (req.query.name__in) {
        const set = new Set(String(req.query.name__in).split(','));
        out = out.filter(x => set.has(String(x[nameField])));
      } else if (req.query.name) {
        out = out.filter(x =>
          String(x[nameField]).includes(String(req.query.name)),
        );
      }
      if (req.query.organization) {
        out = out.filter(
          x => Number(x.organization) === Number(req.query.organization),
        );
      }
      return out;
    },
  };

  return store;
}
