---
name: portal-onboard
description: >-
  Onboard a new developer to automation-portal-local. Clones required repos,
  creates .env, and explains which dev loop to use. Activate when the user says
  "onboard", "set me up", "getting started", or "new developer setup".
---

# Onboarding — Automation Portal Local

Walk the developer through first-time setup interactively.
Ask questions at each stage rather than dumping everything at once.

## Step 1 — Prerequisites check

Verify these are installed before proceeding:

```bash
podman --version        # 4.x+
git --version
node --version          # 22.x preferred
make --version
tox --version           # for make apme (uv tool install tox --with tox-uv)
```

If anything is missing, tell the user what to install and stop.

## Step 2 — Clone this repo (skip if already cloned)

```bash
git clone --recurse-submodules <repo-url>
cd automation-portal-local
```

If the user already has the repo, verify the submodule is initialized:

```bash
git submodule update --init --recursive
```

## Step 3 — Determine which dev loop they need

Ask the user:

> **What kind of work will you be doing?**
>
> A. **Editing plugin source** (TypeScript/React in ansible-backstage-plugins)
>    → You need the **dev mount loop** (`make dev`).
>
> B. **Production-shaped tarballs** (same install path as OpenShift / EAP)
>    → You need the **tarball loop** (`make start`). Builds from `PLUGIN_REPO`
>      by default; use `SKIP_BUILD=1` only for pre-downloaded CI `.tgz`.

### If they chose A (dev mount loop) or B with local build

They need local clones of **ansible-backstage-plugins** and **apme**:

```bash
git clone git@github.com:ansible/ansible-backstage-plugins.git
git clone git@github.com:ansible/apme.git
```

Note the paths — they become `PLUGIN_REPO` and `APME_REPO` in the next step.

### If they chose B with CI/EAP artifacts only (no source)

They need `.tgz` plugin tarballs already in `local-plugins/portal/` from:

- CI artifacts from the ansible-rhdh-plugins early-access workflow
- A pre-built EAP tar distribution

Then: `make start SKIP_BUILD=1` with `PORTAL_ONLY=1` (no APME clone required).

## Step 4 — Create .env

```bash
cp .env.example .env
```

Then walk through the file with the user. Key decisions:

| Variable | Needs editing? | Notes |
|---|---|---|
| `PLUGIN_REPO` | **Yes** for `make dev` / `make start` (unless `SKIP_BUILD=1`) | Absolute path to ansible-backstage-plugins clone |
| `APME_REPO` | Usually default is fine | Absolute path to apme clone (`make apme` → `tox -e up`) |
| `AAP_MOCK` | Usually no | Default `1` uses the built-in mock (user/password) |
| `GITHUB_TOKEN` | Optional | Only needed for real SCM push/PR operations |
| `PORTAL_ONLY` | Only for IAG / no Quality | `1` skips APME plugins and `make apme` |

Everything else has sensible defaults for local development. Additional
overrides (`FORCE_EXPORT`, `DEV_PROMPT`, `SKIP_BUILD`) are documented in
`make help` — don't mention them unless the user asks.

## Step 5 — First run

### Dev mount loop

```bash
make dev
# Portal UI:       http://localhost:7007
# APME Gateway:    http://localhost:8080  (via make apme / tox -e up)
# Almost like AAP: http://localhost:8099
# Login:           user / password
```

`make dev` probes the Gateway and runs `make apme` if it is down.

After compose is up, an interactive menu appears:

```
[R] reload     [F] frontend     [S] stop     [Q] quit menu
```

- **R** — re-export changed plugins + reinstall + restart rhdh (`make reload`)
- **F** — frontend-only export, browser refresh, no restart (`make reload-fe`)
- **S** — stop Portal services (`make stop`; APME keeps running)
- **Q** — quit the menu (services keep running)

Both **R** and **F** are incremental — only plugins with source changes are
re-exported. Use `FORCE_EXPORT=1` to rebuild everything.

The menu can be re-entered later with `make dev-prompt`, or bypassed entirely
with `make dev DEV_PROMPT=0`. You can always use `make reload` / `make reload-fe`
directly from another terminal.

### Tarball loop

```bash
make start                          # ensure APME + export + pack from PLUGIN_REPO
make start SKIP_BUILD=1             # reuse existing local-plugins/portal/*.tgz
# Same URLs as above
```

## Step 6 — Explain the day-to-day loop

Summarize for the user:

**Dev mount loop** — Your plugin source (`dist-dynamic`) is bind-mounted into
RHDH. After startup an interactive menu lets you press **R** (reload changed
plugins), **F** (frontend only, no restart), or **S** (stop Portal). Both are
incremental — only re-export plugins whose source changed. You can also run
`make reload` / `make reload-fe` from another terminal. This is **not**
webpack HMR — RHDH reloads from the mounted files on restart.

**Tarball loop** — `make start` builds `.tgz` from `PLUGIN_REPO` and installs
them exactly like production (same as the Helm chart on OpenShift). Faster
day-to-day iteration still prefers `make dev` + `make reload`.

**APME** — lives in its own clone. `make apme` runs `tox -e up`; `make
apme-down` stops it. Portal compose does not bundle gateway/validators/Abbenay.
Abbenay keys go in `APME_REPO/containers/abbenay/.env`.

Stop Portal with `make stop`. Run `make help` to see all available targets.
