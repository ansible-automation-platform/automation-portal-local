# Automation Portal Local

Run the Automation Portal (RHDH + Portal plugins) locally with Podman Compose. Optionally includes APME and a mock AAP server for development.

This repository wraps [rhdh-local](https://github.com/redhat-developer/rhdh-local) as a git submodule and adds Portal configuration overlays, scripts, and an EAP distribution workflow. It uses RHDH's [dynamic plugin loading](https://docs.redhat.com/en/documentation/red_hat_developer_hub/) — the same mechanism used in production — so local testing matches the deployed experience.

## Table of Contents

- [Customer Quick Start](#customer-quick-start)
- [Developer Quick Start](#developer-quick-start)
- [Deployment Modes](#deployment-modes)
- [Prerequisites](#prerequisites)
- [Getting Plugins](#getting-plugins)
- [Environment Variables](#environment-variables)
- [Make Targets](#make-targets)
- [EAP Distribution](#eap-distribution)
- [Platform Notes](#platform-notes)
- [Architecture](#architecture)
- [How Dynamic Plugin Loading Works](#how-dynamic-plugin-loading-works)
- [Repository Structure](#repository-structure)
- [Adding More Integrations](#adding-more-integrations)
- [Relationship to Other Repos](#relationship-to-other-repos)

## Customer Quick Start

For EAP customers testing portal features (e.g. multi-org) with a real AAP controller:

```bash
# 1. Untar
tar xzf automation-portal-local-*.tar.gz && cd automation-portal-local

# 2. Configure
cp .env.example .env
# Edit .env — set AAP_HOST_URL, AAP_PUBLIC_URL, AAP_TOKEN, OAUTH_CLIENT_ID,
#              OAUTH_CLIENT_SECRET. Set AAP_MOCK=0 and APME_EXTERNAL=1.

# 3. Start
make start SKIP_BUILD=1
```

Portal UI: http://localhost:7007

**Updating plugins:** Copy new `.tgz` files to `local-plugins/portal/`, then `make stop && make start SKIP_BUILD=1`.

**Cleanup:** `make stop` (stop services) or `make clean` (stop + remove volumes).

## Developer Quick Start

Day-to-day plugin work mounts each plugin's `dist-dynamic` into RHDH. No `.tgz` packaging, no OCI publish. Uses the built-in mock AAP server by default.

```bash
# 1. Clone with submodules
git clone --recurse-submodules <repo-url>
cd automation-portal-local

# 2. Set environment variables
cp .env.example .env
# Edit .env — set PLUGIN_REPO to your ansible-backstage-plugins clone

# 3. Start (exports dist-dynamic, mounts them, starts compose)
make dev
```

Portal UI: http://localhost:7007
Almost like AAP (mock): http://localhost:8099

**Login:** Sign in with Ansible Automation Platform → mock page → `user` / `password`.

```bash
# Interactive menu after make dev (TTY):
#   [R] reload   [F] frontend   [S] stop   [Q] quit menu
# Or from another shell:
make reload                         # re-export changed plugins + restart rhdh
make reload PLUGINS=backstage-apme  # one plugin
make reload-fe                      # FE only (browser refresh, no restart)
```

This is **not** webpack HMR — RHDH reloads mounted files on container restart.

## Deployment Modes

### Portal-only (no APME, no mock)

For EAP testing with a real AAP controller:

```bash
# In .env
AAP_MOCK=0
APME_EXTERNAL=1
AAP_HOST_URL=https://your-aap-controller.example.com
AAP_PUBLIC_URL=https://your-aap-controller.example.com
AAP_TOKEN=<your-aap-token>
OAUTH_CLIENT_ID=<your-oauth-client-id>
OAUTH_CLIENT_SECRET=<your-oauth-client-secret>
```

Only `db` and `rhdh` containers start. APME and mock services are skipped via compose profiles.

#### Multi-org support

Multi-org is pre-configured in `overlay/app-config.portal-apme.yaml`. Edit the `orgs` list under `catalog.providers.rhaap.<environment>` to match your AAP organizations:

```yaml
catalog:
  providers:
    rhaap:
      development:
        multiOrgEnabled: true
        orgs:
          - Default
          - Engineering
```

### Full stack (Portal + APME + mock)

Default mode — includes APME quality scanning and a mock AAP server:

```bash
# In .env (defaults)
AAP_MOCK=1              # starts aap-mock container
APME_EXTERNAL=0         # starts full APME stack
```

| Service | URL | Description |
|---|---|---|
| Portal UI | http://localhost:7007 | RHDH with portal plugins |
| APME Gateway | http://localhost:8080 | Quality scanning API |
| APME UI | http://localhost:8081 | Native APME SPA (toggle with `APME_UI`) |
| Almost like AAP | http://localhost:8099 | Mock AAP controller + OAuth |

### External APME (skip compose stack)

Point Portal at an APME Gateway you already run (e.g. `tox -e up` in the [apme](https://github.com/ansible/apme) repo):

```bash
# In .env
APME_EXTERNAL=1
# APME_BASE_URL=http://host.containers.internal:8080   # default when external
```

### Toggling services

| Variable | Default | Effect |
|---|---|---|
| `AAP_MOCK=0` | `1` (on) | Disables mock AAP server — use real AAP credentials |
| `APME_EXTERNAL=1` | `0` (bundled) | Disables APME stack — portal-only |
| `APME_UI=0` | `1` (on) | Disables native APME SPA (keep gateway + validators) |

## Prerequisites

- **Podman** 4.x+ with `podman compose`
- **git** (for submodule management)
- **Node.js** 22.x + Corepack (for building plugins locally — not needed for `SKIP_BUILD=1`)
- **8 GB+ RAM** (RHDH + PostgreSQL; +4 GB when APME stack is enabled)

## Getting Plugins

### Option A: Mount `dist-dynamic` (recommended for developers)

`make dev` runs `yarn export-dynamic` per portal plugin and bind-mounts each `plugins/<name>/dist-dynamic` into RHDH. Config: `overlay/dynamic-plugins.portal-apme.dev.yaml`.

| Plugin directory | Mounted as |
|---|---|
| `auth-backend-module-rhaap-provider` | `local-plugins/portal-dev/auth-backend-module-rhaap-provider` |
| `catalog-backend-module-rhaap` | `local-plugins/portal-dev/catalog-backend-module-rhaap` |
| `self-service` | `local-plugins/portal-dev/self-service` |
| `scaffolder-backend-module-backstage-rhaap` | `local-plugins/portal-dev/scaffolder-backend-module-backstage-rhaap` |
| `backstage-apme` (optional) | `local-plugins/portal-dev/backstage-apme` |
| `catalog-backend-module-apme` (optional) | `local-plugins/portal-dev/catalog-backend-module-apme` |

```bash
make dev PLUGIN_REPO=/path/to/ansible-backstage-plugins
make reload
```

Do **not** use upstream `BUILD_TYPE=portal ./build.sh` for this loop — that mode can delete `plugins/backstage-rhaap`. Prefer `make export-plugins`.

### Option B: Tarball pack (EAP / production-shaped)

`make start` **builds** portal plugins from `PLUGIN_REPO` (export-dynamic + npm pack into `local-plugins/portal/`), updates tarball filenames in the overlay YAML, then starts compose. Same install path as OpenShift.

```bash
make start PLUGIN_REPO=/path/to/ansible-backstage-plugins
# or just make start  if PLUGIN_REPO is set in .env
```

Rebuild only (no compose): `make build-plugins`. Skip rebuild when using CI-downloaded `.tgz`: `make start SKIP_BUILD=1`.

| Plugin | Package | Required |
|---|---|---|
| auth-backend-module-rhaap-provider | `ansible-backstage-plugin-auth-backend-module-rhaap-provider-dynamic-*.tgz` | Always |
| catalog-backend-module-rhaap | `ansible-backstage-plugin-catalog-backend-module-rhaap-dynamic-*.tgz` | Always |
| self-service | `ansible-plugin-backstage-self-service-dynamic-*.tgz` | Always |
| scaffolder-backend-module-backstage-rhaap | `ansible-plugin-scaffolder-backend-module-backstage-rhaap-dynamic-*.tgz` | Always |
| backstage-apme | `ansible-plugin-backstage-apme-dynamic-*.tgz` | APME only |
| catalog-backend-module-apme | `ansible-backstage-plugin-catalog-backend-module-apme-dynamic-*.tgz` | APME only |

### Option C: Download from GitHub Actions workflow (for PMs, QE, EAP)

Use this when you want pre-built plugins from a CI run — no local Node.js or build tools required.

**From ansible-rhdh-plugins early-access workflow:**

1. Go to [ansible-rhdh-plugins Actions](https://github.com/ansible-automation-platform/ansible-rhdh-plugins/actions/workflows/release-plugins.yaml)
2. Click **Run workflow** with:
   - `release_type`: `early-access`
   - `upstream_branch`: the branch to build from (e.g. `main`)
3. When complete, download the **plugin tarballs** artifact
4. Extract into `local-plugins/portal/`:
   ```bash
   tar -xzf early-access-plugins-*.tar.gz -C local-plugins/portal/
   ```
5. Start with `make start SKIP_BUILD=1`

**From automation-portal-local EAP workflow:** see [EAP Distribution](#eap-distribution).

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `AAP_HOST_URL` | Yes | — | AAP controller URL (e.g. `https://aap.example.com`) |
| `AAP_PUBLIC_URL` | Yes | same as `AAP_HOST_URL` | AAP URL reachable from the browser (for OAuth redirect) |
| `AAP_TOKEN` | Yes | — | AAP API token |
| `OAUTH_CLIENT_ID` | Yes | — | RHAAP OAuth client ID |
| `OAUTH_CLIENT_SECRET` | Yes | — | RHAAP OAuth client secret |
| `AAP_MOCK` | No | `1` (on) | `0` disables mock AAP server (use real AAP credentials) |
| `GITHUB_TOKEN` | No | — | GitHub PAT for SCM integration |
| `PLUGIN_REPO` | Yes for `dev` | `~/github/ansible-backstage-plugins` | Absolute path to ansible-backstage-plugins |
| `GITHUB_OAUTH_CLIENT_ID` | No | — | GitHub OAuth app client ID |
| `GITHUB_OAUTH_CLIENT_SECRET` | No | — | GitHub OAuth app client secret |
| `GITLAB_TOKEN` | No | — | GitLab PAT (if using GitLab SCM) |
| `APME_IMAGE_TAG` | No | `latest` | APME container image tag from ghcr.io |
| `APME_UI` | No | `1` (on) | Start native APME SPA; `0` to skip; forced off when `APME_EXTERNAL=1` |
| `APME_EXTERNAL` | No | `0` (bundled) | `1` skips compose APME stack and uses `APME_BASE_URL` |
| `APME_BASE_URL` | No | auto-detected | Gateway URL for RHDH / APME plugins |
| `RHDH_IMAGE` | No | `quay.io/rhdh-community/rhdh:1.10` | RHDH base image |
| `CUSTOMER_SUPPORT_URL` | No | Red Hat support | URL for the Support button in the global header |
| `POSTGRES_PASSWORD` | No | `postgres` | PostgreSQL password |
| `NODE_TLS_REJECT_UNAUTHORIZED` | No | `0` | Set to `0` for self-signed certs |

## Make Targets

Run `make help` to see all targets. Key ones:

| Target | Description |
|---|---|
| `make dev` | **Dev loop:** export-dynamic + mount `dist-dynamic` + compose up |
| `make start` | Tarball mode: **build** `.tgz` from `PLUGIN_REPO`, then start (`SKIP_BUILD=1` to reuse) |
| `make check-plugin-parity` | Verify DEV vs tarball `pluginConfig` consistency (enabled plugins only) |
| `make stop` | Stop all services (auto-detects mode) |
| `make reload` | Re-export **changed** plugins + reinstall + restart rhdh (`FORCE_EXPORT=1` = all) |
| `make reload-fe` | FE-only: incremental export of dirty FE plugins into `dynamic-plugins-root` |
| `make export-plugins` | Incremental `yarn export-dynamic` for portal plugins |
| `make build-plugins` | Build dynamic plugin **tarballs** (EAP / ship-shape) |
| `make clean` | Stop services, remove volumes, clean copied overlay files |
| `make clean-images` | Full cleanup including container images |
| `make logs` | Follow compose logs |
| `make status` | Show running containers |

Override `PLUGIN_REPO`, `PLUGINS`, or `FE_PLUGINS` on the command line, e.g. `make reload PLUGINS=backstage-apme`.

**Host contract:** RHDH registers apiFactories/routes/mountPoints from overlay YAML, not from the plugin package alone. Changing these requires updating **both** `overlay/dynamic-plugins.portal-apme.dev.yaml` and `overlay/dynamic-plugins.portal-apme.yaml`. CI and `make check-plugin-parity` enforce consistency for enabled plugins.

## EAP Distribution

For PMs and EAP coordinators — produce a self-contained tar that customers can run without git, Node.js, or build tools.

### Packaging a distributable tarball

**Option 1: EAP workflow (recommended)**

1. Go to **Actions** > **EAP / Build Distributable**
2. Fill in inputs:
   - `plugin_source`: `upstream_branch` (build from source) or `artifact_download` (use pre-built)
   - `upstream_branch`: e.g. `main` or `feat/sync-ux-signals`
   - `apme_image_tag`: APME version (e.g. `latest`, `2026.7.3`)
   - `rhdh_image`: RHDH base image (default: `quay.io/rhdh-community/rhdh:1.10`)
3. Download the `automation-portal-local-*.tar.gz` artifact (retained for 30 days)

**Option 2: Manual packaging**

```bash
# 1. Build plugins from a specific branch
cd /path/to/ansible-backstage-plugins
git checkout main

# 2. Build plugin tarballs
cd /path/to/automation-portal-local
make build-plugins PLUGIN_REPO=/path/to/ansible-backstage-plugins

# 3. Verify (optional)
make start SKIP_BUILD=1
make stop

# 4. Package
tar czf automation-portal-local-multiorg.tar.gz \
  --exclude='.git' --exclude='node_modules' \
  --exclude='rhdh-local/.git' --exclude='*.log' \
  -C /path/to automation-portal-local
```

### Updating plugins (EAP drops)

To provide customers with updated plugins without rebuilding the full tarball:

1. Copy new `.tgz` files to the customer host:
   ```bash
   scp new-plugins/*.tgz user@host:automation-portal-local/local-plugins/portal/
   ```
2. Reinstall and restart:
   ```bash
   make stop && make start SKIP_BUILD=1
   ```

## Platform Notes

### macOS (Apple Silicon)

APME container images are `linux/amd64` only. On ARM hosts:
- Auto-sets `APME_PLATFORM=linux/amd64` for Rosetta/QEMU emulation
- APME scans ~2-5x slower due to emulation
- **Known limitation:** APME "Push branch" and "Create PR" fail under ARM emulation (`SSL: CERTIFICATE_VERIFY_FAILED`). Scan and review work normally.

### Linux (x86_64 — Fedora, CentOS, RHEL)

Native performance. No emulation needed. Target platform for EAP customers.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Podman Compose                                          │
│                                                          │
│  ┌──────────┐  ┌────────────────┐  ┌─────────────────┐  │
│  │ install- │  │      rhdh      │  │       db        │  │
│  │ dynamic- │→ │  (Portal UI)   │← │  (PostgreSQL)   │  │
│  │ plugins  │  │   :7007        │  │                 │  │
│  └──────────┘  └────────────────┘  └─────────────────┘  │
│                        │                                 │
│           ┌────────────┴────────────┐                    │
│           │  Optional (profiles)    │                    │
│           ▼                         ▼                    │
│  ┌─────────────────┐    ┌───────────────────────┐        │
│  │    aap-mock     │    │    apme-gateway        │        │
│  │  profile: mock  │    │    profile: apme       │        │
│  │    :8099        │    │    :8080               │        │
│  └─────────────────┘    └───────────┬───────────┘        │
│                                     ▼                    │
│                         ┌───────────────────────┐        │
│                         │   apme-primary        │        │
│                         │   + validators        │        │
│                         │   profile: apme       │        │
│                         └───────────────────────┘        │
└──────────────────────────────────────────────────────────┘
```

## How Dynamic Plugin Loading Works

### Tarball / EAP (`make start`)

1. Export + pack plugins from `PLUGIN_REPO` into `local-plugins/portal/*.tgz` (unless `SKIP_BUILD=1`)
2. `install-dynamic-plugins` extracts them into the shared `dynamic-plugins-root` volume
3. `rhdh` starts with those installed plugins
4. Config: `dynamic-plugins.portal-apme.yaml`

Matches how the Helm chart ([ansible-portal-chart](https://github.com/ansible-automation-platform/ansible-portal-chart)) loads plugins in OpenShift.

### Mount / DEV (`make dev`)

1. Host `plugins/*/dist-dynamic` is bind-mounted under `local-plugins/portal-dev/`
2. Override YAML uses `package: ./local-plugins/portal-dev/<name>`
3. Host `./dynamic-plugins-root` is mounted into RHDH
4. Iterate: `make reload` (reinstall + restart) or `make reload-fe` (browser refresh)

If plugins vanish after install, check `dynamic-plugins-root/dynamic-plugins.extensions.yaml` — it must use `includes: []`.

## Repository Structure

```
automation-portal-local/
├── Makefile                        # Primary interface (make help)
├── .github/workflows/
│   ├── eap-build.yaml              # EAP distributable build workflow
│   └── update-submodule.yaml       # Weekly rhdh-local submodule update
├── rhdh-local/                     # git submodule (redhat-developer/rhdh-local)
├── overlay/
│   ├── compose.portal-apme.yaml           # Compose overlay (services + profiles)
│   ├── compose.portal-apme.dev.yaml       # Bind-mount dist-dynamic (DEV)
│   ├── app-config.portal-apme.yaml        # Portal app-config
│   ├── dynamic-plugins.portal-apme.yaml   # Plugin manifest (tarballs)
│   └── dynamic-plugins.portal-apme.dev.yaml
├── aap-mock/                       # Local AAP mock (profile: mock)
├── local-plugins/portal/           # Plugin tarballs (gitignored)
├── scripts/
│   ├── build-plugins.sh            # Pack tarballs from upstream clone
│   ├── export-plugins-dev.sh       # yarn export-dynamic for portal plugins
│   ├── load-images.sh              # Load OCI archives for offline EAP
│   └── lib.sh                      # Minimal shared helpers
├── .env.example
└── README.md
```

## Adding More Integrations

The compose overlay pattern is extensible. To add another integration (e.g. Lightspeed):

1. Create a new compose overlay: `overlay/compose.portal-lightspeed.yaml`
2. Add the `-f` flag to `COMPOSE_F` in the Makefile
3. Add a compose profile for the new service
4. Update the EAP workflow to pull/save additional container images

## Relationship to Other Repos

| Repo | Role | Analogy |
|---|---|---|
| **automation-portal-local** (this repo) | Local compose wrapper over rhdh-local | Like `ansible-portal-chart` wraps `rhdh-chart` |
| [rhdh-local](https://github.com/redhat-developer/rhdh-local) | Base RHDH compose setup (submodule) | Like `redhat-developer-hub` Helm chart |
| [ansible-backstage-plugins](https://github.com/ansible/ansible-backstage-plugins) | Portal plugin source code | Plugin source |
| [ansible-rhdh-plugins](https://github.com/ansible-automation-platform/ansible-rhdh-plugins) | Plugin packaging + early-access CI | CI/CD for plugin tarballs + OCI images |
| [ansible-portal-chart](https://github.com/ansible-automation-platform/ansible-portal-chart) | Helm chart (OpenShift/K8s) | Production deployment |
| [apme](https://github.com/ansible/apme) | APME engine source + container images | Engine containers on ghcr.io |
