# Automation Portal Local

Run the Automation Portal (RHDH + Portal plugins + APME) locally with Podman Compose.

This repository wraps [rhdh-local](https://github.com/redhat-developer/rhdh-local) as a git submodule and adds Portal + APME configuration overlays, scripts, and an EAP distribution workflow. It uses RHDH's [dynamic plugin loading](https://docs.redhat.com/en/documentation/red_hat_developer_hub/) — the same mechanism used in production — so local testing matches the deployed experience.

## Quick Start (Developer — mount loop)

Day-to-day plugin work mounts each plugin’s `dist-dynamic` into RHDH. No `.tgz` packaging, no OCI publish. **No real AAP required** — compose starts **Almost like AAP** (`aap-mock`).

```bash
# 1. Clone with submodules
git clone --recurse-submodules <repo-url>
cd automation-portal-local

# 2. Set environment variables
cp .env.example .env
# Edit .env — PLUGIN_REPO (and optional GITHUB_TOKEN). Mock AAP defaults are fine.

# 3. Start (exports dist-dynamic, mounts them, starts compose + aap-mock)
make dev
# Or override PLUGIN_REPO on the command line:
make dev PLUGIN_REPO=/path/to/ansible-backstage-plugins
```

Portal UI: http://localhost:7007  
APME Gateway: http://localhost:8080  
APME UI (native SPA): http://localhost:8081 — toggle with `APME_UI` in `.env` (default on)  
Almost like AAP: http://localhost:8099  

**Login:** Sign in with Ansible Automation Platform → mock page **Almost like AAP** → `user` / `password`.

```bash
# After make dev, use the interactive menu (TTY):
#   [R] reload   [F] frontend   [S] stop   [Q] quit menu
# Or from another shell:
make reload                         # re-export changed plugins + restart rhdh
make reload PLUGINS=backstage-apme  # one plugin
make reload-fe                      # FE only (browser refresh, no restart)
make dev-prompt                     # re-enter the R/F/S menu
```

This is **not** webpack HMR — RHDH reloads mounted files on container restart. For EAP / ship-shape tarball parity, use `make start` (builds tarballs from `PLUGIN_REPO`, then starts). To use a real Controller instead of the mock, set `AAP_MOCK=0` and real `AAP_*` / OAuth values.

### External APME (skip compose stack)

Point Portal at an APME Gateway you already run (e.g. `tox -e up` in the [apme](https://github.com/ansible/apme) repo) instead of starting `apme-*` containers:

```bash
# In .env
APME_EXTERNAL=1
# APME_BASE_URL=http://host.containers.internal:8080   # default when external
```

Then `make dev` (or `make start`). Compose will not start gateway/primary/validators/Abbenay/`apme-ui`; RHDH reaches the host Gateway via `host.containers.internal`. Use the external stack’s own UI (typically http://localhost:8081). Flip back with `APME_EXTERNAL=0` (or unset) and recreate so profile `apme` is active again.

### Bundled Abbenay (AI / Tier 2)

When `APME_EXTERNAL=0`, compose starts **`apme-abbenay`** alongside the gateway and engine (compose network only — no host ports for `:8787` / `:50057`).

```bash
cp .env-abbenay.example .env-abbenay   # add OPENROUTER_API_KEY (etc.)
# optional: edit rhdh-local/abbenay-config/config.yaml after first start
make start   # or make dev
```

Provider keys are injected via `.env-abbenay` at container start (restart Abbenay after edits). With `APME_EXTERNAL=1`, use the host APME checkout `containers/abbenay/.env` instead — portal `.env-abbenay` is unused.

### Portal-only mode (no APME, no mock)

For EAP testing with a real AAP controller — no APME stack, no mock server:

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

To re-enable APME or the mock server, set the corresponding variables back to their defaults:

| Variable | Default | Effect |
|---|---|---|
| `AAP_MOCK=1` | on | Starts the `aap-mock` container (local OAuth + API mock) |
| `APME_EXTERNAL=0` | bundled | Starts the full APME stack (gateway, validators, UI) |

Multi-org support is pre-configured in `overlay/app-config.portal-apme.yaml`. Edit the `orgs` list under `catalog.providers.rhaap.<environment>` to match your AAP organizations:

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

### Updating plugins (EAP drops)

To provide customers with an updated set of plugins without rebuilding the full tarball:

1. Copy the new `.tgz` files to the customer host:
   ```bash
   scp new-plugins/*.tgz user@customer-host:automation-portal-local/local-plugins/portal/
   ```

2. On the customer host, reinstall and restart:
   ```bash
   cd automation-portal-local
   make stop
   make start SKIP_BUILD=1
   ```

### Packaging a distributable tarball

To create a self-contained tarball for customer delivery:

**Option 1: EAP workflow (recommended)**

1. Go to **Actions** > **EAP / Build Distributable** in this repo
2. Set `upstream_branch` to the branch with your changes (e.g. `main`, `feat/sync-ux-signals`)
3. Download the `automation-portal-local-*.tar.gz` artifact

**Option 2: Manual packaging**

```bash
# 1. Build plugins from a specific branch
cd /path/to/ansible-backstage-plugins
git checkout main   # or feat/sync-ux-signals

# 2. Build plugin tarballs
cd /path/to/automation-portal-local
make build-plugins PLUGIN_REPO=/path/to/ansible-backstage-plugins

# 3. Verify (optional — starts portal, confirm it works, then stop)
make start SKIP_BUILD=1
make stop

# 4. Package (exclude dev files, git, node_modules)
tar czf automation-portal-local-multiorg.tar.gz \
  --exclude=’.git’ \
  --exclude=’node_modules’ \
  --exclude=’rhdh-local/.git’ \
  --exclude=’*.log’ \
  -C /path/to \
  automation-portal-local
```

### Customer quick start (3 commands)

```bash
# 1. Untar
tar xzf automation-portal-local-multiorg.tar.gz && cd automation-portal-local

# 2. Configure
cp .env.example .env
# Edit .env — set AAP_HOST_URL, AAP_PUBLIC_URL, AAP_TOKEN, OAUTH_CLIENT_ID,
#              OAUTH_CLIENT_SECRET. Set AAP_MOCK=0 and APME_EXTERNAL=1.

# 3. Start
make start SKIP_BUILD=1
```

Portal UI: http://localhost:7007

### Customer cleanup

```bash
make stop          # Stop services
make clean         # Full cleanup (removes volumes and data)
```

## Prerequisites

- **Podman** 4.x+ with `podman compose`
- **git** (for submodule management)
- **Node.js** 22.x + Corepack (for building plugins locally)
- **8 GB+ RAM** (RHDH + APME stack + PostgreSQL; +1 container when `APME_UI=1`)

## Getting Plugins

### Option A: Mount `dist-dynamic` (recommended for developers)

`make dev` runs `yarn export-dynamic` per portal plugin and bind-mounts each `plugins/<name>/dist-dynamic` into RHDH at `dynamic-plugins-root/dev-<name>`. Config: `overlay/dynamic-plugins.portal-apme.dev.yaml`.

| Plugin directory | Mounted as |
|---|---|
| `auth-backend-module-rhaap-provider` | `local-plugins/portal-dev/auth-backend-module-rhaap-provider` |
| `catalog-backend-module-rhaap` | `local-plugins/portal-dev/catalog-backend-module-rhaap` |
| `self-service` | `local-plugins/portal-dev/self-service` |
| `scaffolder-backend-module-backstage-rhaap` | `local-plugins/portal-dev/scaffolder-backend-module-backstage-rhaap` |
| `backstage-apme` | `local-plugins/portal-dev/backstage-apme` |
| `catalog-backend-module-apme` | `local-plugins/portal-dev/catalog-backend-module-apme` |

```bash
# PLUGIN_REPO in .env, or override:
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

| Plugin | Package | Description |
|---|---|---|
| auth-backend-module-rhaap-provider | `ansible-backstage-plugin-auth-backend-module-rhaap-provider-dynamic-*.tgz` | AAP OAuth authentication |
| catalog-backend-module-rhaap | `ansible-backstage-plugin-catalog-backend-module-rhaap-dynamic-*.tgz` | AAP catalog sync (collections, templates, orgs) |
| self-service | `ansible-plugin-backstage-self-service-dynamic-*.tgz` | Portal frontend (landing page, routing, field extensions) |
| scaffolder-backend-module-backstage-rhaap | `ansible-plugin-scaffolder-backend-module-backstage-rhaap-dynamic-*.tgz` | Custom scaffolder actions |
| backstage-apme | `ansible-plugin-backstage-apme-dynamic-*.tgz` | APME frontend (Quality tab, scan workflow) |
| catalog-backend-module-apme | `ansible-backstage-plugin-catalog-backend-module-apme-dynamic-*.tgz` | APME backend (gateway proxy, catalog sync) |

### Option C: Download from GitHub Actions workflow (for PMs, QE, EAP)

Use this when you want pre-built plugins from a CI run — no local Node.js or build tools required.

**From ansible-rhdh-plugins early-access workflow:**

1. Go to [ansible-rhdh-plugins Actions](https://github.com/ansible-automation-platform/ansible-rhdh-plugins/actions/workflows/release-plugins.yaml)
2. Click **Run workflow** with:
   - `release_type`: `early-access`
   - `upstream_branch`: the branch to build from (e.g. `feat/apme-eap-next-ui-workflow`)
3. When complete, download the **plugin tarballs** artifact
4. Extract into `local-plugins/portal/`:
   ```bash
   # The artifact contains a bundle tar.gz
   tar -xzf early-access-plugins-*.tar.gz -C local-plugins/portal/
   ```
5. Update `overlay/dynamic-plugins.portal-apme.yaml` tarball filenames to match the downloaded versions (or place them and run `make start SKIP_BUILD=1` after editing the YAML). Local builds update filenames automatically via `make build-plugins` / `make start`.

**From automation-portal-local EAP workflow:**

1. Go to **Actions** > **EAP / Build Distributable** in this repo
2. Fill in inputs (see [EAP Distribution](#eap-distribution) below)
3. The workflow builds plugins, pulls APME images, and packages everything into a distributable tar

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `AAP_HOST_URL` | Yes | — | AAP controller URL (e.g. `https://aap.example.com`) |
| `AAP_PUBLIC_URL` | Yes | same as `AAP_HOST_URL` | AAP URL reachable from the browser (for OAuth redirect) |
| `AAP_TOKEN` | Yes | — | AAP API token |
| `OAUTH_CLIENT_ID` | Yes | — | RHAAP OAuth client ID |
| `OAUTH_CLIENT_SECRET` | Yes | — | RHAAP OAuth client secret |
| `AAP_MOCK` | No | `1` (on) | `0` disables the mock AAP server (use real AAP credentials) |
| `GITHUB_TOKEN` | Yes | — | GitHub PAT for SCM integration |
| `PLUGIN_REPO` | Yes for `start-dev` | `~/github/ansible-backstage-plugins` | Absolute path to ansible-backstage-plugins |
| `GITHUB_OAUTH_CLIENT_ID` | No | — | GitHub OAuth app client ID |
| `GITHUB_OAUTH_CLIENT_SECRET` | No | — | GitHub OAuth app client secret |
| `GITLAB_TOKEN` | No | — | GitLab PAT (if using GitLab SCM) |
| `APME_IMAGE_TAG` | No | `latest` | APME container image tag from ghcr.io |
| `ABBENAY_IMAGE_TAG` | No | `v2026.8.1` | Abbenay image tag (bundled compose only) |
| `APME_ABBENAY_TOKEN` | No | `apme-dev-token` | Shared token Primary/Gateway ↔ Abbenay |
| `APME_AI_MODEL` | No | _(empty)_ | Optional default model id for Primary |
| `APME_UI` | No | `1` (on) | Start native APME SPA (`apme-ui`) for side-by-side testing; `0`/`false`/`off` to skip; forced off when `APME_EXTERNAL=1` |
| `APME_UI_PORT` | No | `8081` | Host port for the native APME UI |
| `APME_EXTERNAL` | No | `0` (bundled) | `1` skips compose `apme-*` (incl. Abbenay) and uses `APME_BASE_URL` |
| `APME_BASE_URL` | No | bundled: `http://apme-gateway:8080`; external: `http://host.containers.internal:8080` | Gateway URL for RHDH / APME plugins |
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
| `make check-plugin-parity` | Fail if DEV vs tarball `pluginConfig` host contracts drift |
| `make stop` | Stop all services (auto-detects dev vs tarball mode) |
| `make reload` | Re-export **changed** plugins + reinstall + restart rhdh (`FORCE_EXPORT=1` = all) |
| `make reload-fe` | FE-only: incremental export of dirty FE plugins into `dynamic-plugins-root` |
| `make export-plugins` | Incremental `yarn export-dynamic` for portal plugins |
| `make build-plugins` | Build dynamic plugin **tarballs** (EAP / ship-shape) |
| `make clean` | Stop services, remove volumes, clean copied overlay files |
| `make clean-images` | Full cleanup including container images |
| `make logs` | Follow compose logs |
| `make status` | Show running containers |

Override `PLUGIN_REPO`, `PLUGINS`, or `FE_PLUGINS` on the command line, e.g. `make reload PLUGINS=backstage-apme`.

**Host contract:** RHDH registers APME/self-service `apiFactories` from overlay YAML, not from the package alone. Changing factories/routes/mountPoints requires updating **both** `overlay/dynamic-plugins.portal-apme.dev.yaml` and `overlay/dynamic-plugins.portal-apme.yaml`. See [AGENTS.md](AGENTS.md). CI and `make check-plugin-parity` enforce this.

## EAP Distribution

For PMs and EAP coordinators — produce a self-contained tar that customers can run without git, Node.js, or build tools.

### Running the EAP workflow

1. Go to **Actions** > **EAP / Build Distributable**
2. Fill in inputs:
   - `plugin_source`: `upstream_branch` (build from source) or `artifact_download` (use pre-built from ansible-rhdh-plugins)
   - `upstream_branch`: e.g. `feat/apme-eap-next-ui-workflow` (if building from source)
   - `artifact_run_id`: workflow run ID from ansible-rhdh-plugins (if using pre-built)
   - `apme_image_tag`: APME version (e.g. `latest`, `2026.7.3`)
   - `rhdh_image`: RHDH base image (default: `quay.io/rhdh-community/rhdh:1.10`)
   - `node_version`: Node.js version for plugin builds (default: `22.x`)
3. Download the `automation-portal-local-*.tar.gz` artifact (retained for 30 days)

**Note:** The `artifact_download` mode requires a `CROSS_REPO_TOKEN` secret with `actions:read` permission on `ansible-automation-platform/ansible-rhdh-plugins`. The default `GITHUB_TOKEN` is repo-scoped only.

The workflow:
1. Builds or downloads plugin tarballs
2. Pulls APME + PostgreSQL container images from `ghcr.io/ansible` and saves them as multi-arch OCI archives via `skopeo copy --all`
3. Assembles everything into a self-contained directory with rhdh-local base + overlays + plugins + images + scripts
4. Creates a distributable `.tar.gz`

### Customer quick start

```bash
# 1. Untar the archive
tar -xzf automation-portal-local-*.tar.gz
cd automation-portal-local-*

# 2. Set environment variables
cp .env.example .env
# Edit .env — fill in AAP_HOST_URL, AAP_TOKEN, OAUTH credentials, GITHUB_TOKEN

# 3. Start the portal (auto-loads APME images from images/ if present)
make start
```

### Customer cleanup

```bash
# Stop services
make stop

# Full cleanup (removes volumes and data)
make clean

# Full cleanup including container images
make clean-images
```

## Platform Notes

### macOS (Apple Silicon)

APME container images are published as `linux/amd64` only. On ARM hosts:
- `make dev` / `make start` auto-detect ARM and set `APME_PLATFORM=linux/amd64` for Rosetta/QEMU emulation
- Auto-sets `OPENSSL_CONF=/dev/null` to work around UBI10 FIPS provider failures under emulation
- APME scans will be slower (~2-5x) due to emulation overhead
- **Known limitation:** APME's "Push branch" and "Create PR" actions fail with `SSL: CERTIFICATE_VERIFY_FAILED` because OpenSSL 3.x crypto primitives produce incorrect results under ARM emulation. Scan, review, and generate fixes work normally. Push branch / Create PR require a native x86_64 host.

### Linux (x86_64 — Fedora, CentOS, RHEL)

Native performance. No emulation needed. This is the target platform for EAP customers.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Podman Compose                                             │
│                                                             │
│  ┌──────────┐  ┌──────────────────┐  ┌───────────────────┐  │
│  │ install- │  │       rhdh       │  │        db         │  │
│  │ dynamic- │→ │   (Portal UI)    │← │   (PostgreSQL)    │  │
│  │ plugins  │  │   :7007          │  │                   │  │
│  └──────────┘  └──────────────────┘  └───────────────────┘  │
│                         │                                   │
│                         │ /api/catalog/apme                  │
│                         ▼                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              apme-gateway :8080                      │   │
│  │              (REST API + ADR-070 → Abbenay HTTP)     │   │
│  └──────────┬───────────────────────────┬───────────────┘   │
│             │                           │                   │
│             ▼                           ▼                   │
│  ┌────────────────────┐    ┌────────────────────────────┐   │
│  │ apme-primary       │    │ apme-abbenay               │   │
│  │ :50051 (+ sidecars │───▶│ gRPC :50057 / HTTP :8787   │   │
│  │  / galaxy-proxy)   │    │ (.env-abbenay; no hostPort)│   │
│  └────────────────────┘    └────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## How Dynamic Plugin Loading Works

### Tarball / EAP (`make start`)

1. Export + pack plugins from `PLUGIN_REPO` into `local-plugins/portal/*.tgz` (unless `SKIP_BUILD=1`)
2. `install-dynamic-plugins` extracts them into the shared `dynamic-plugins-root` volume
3. `rhdh` starts with those installed plugins
4. Config: `dynamic-plugins.portal-apme.yaml`

Matches how the Helm chart ([ansible-portal-chart](https://github.com/ansible-automation-platform/ansible-portal-chart)) loads plugins in OpenShift.

### Mount / DEV (`make dev`)

1. Host `plugins/*/dist-dynamic` is bind-mounted under `local-plugins/portal-dev/` (installer source path — **not** under `dynamic-plugins-root`, which is wiped on first install / RHIDP-3939)
2. Override YAML uses `package: ./local-plugins/portal-dev/<name>`
3. Host `./dynamic-plugins-root` is mounted into RHDH (same idea as rhdh-local `compose-dynamic-plugins-root.yaml`)
4. Iterate: `make reload` (reinstall + restart) or `make reload-fe` (`export-dynamic --dev` + browser refresh)

If plugins vanish after install, check `dynamic-plugins-root/dynamic-plugins.extensions.yaml` — it must use `includes: []` (including `dynamic-plugins.default.yaml` there can GC portal plugins).

## Repository Structure

```
automation-portal-local/
├── Makefile                        # Primary interface (make help)
├── .github/workflows/
│   ├── eap-build.yaml              # EAP distributable build workflow
│   └── update-submodule.yaml       # Weekly rhdh-local submodule update
├── rhdh-local/                     # git submodule (redhat-developer/rhdh-local)
├── overlay/
│   ├── compose.portal-apme.yaml           # Compose overlay (ghcr.io APME + Abbenay)
│   ├── compose.portal-apme.dev.yaml       # Bind-mount dist-dynamic (DEV)
│   ├── abbenay/config.yaml.example        # Seed for rhdh-local/abbenay-config/
│   ├── app-config.portal-apme.yaml        # Portal app-config
│   ├── dynamic-plugins.portal-apme.yaml   # Plugin manifest (tarballs)
│   └── dynamic-plugins.portal-apme.dev.yaml
├── .env-abbenay.example            # Abbenay provider keys template
├── aap-mock/                       # Local AAP Gateway/Controller/OAuth mock
├── local-plugins/portal/      # Plugin tarballs (gitignored)
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
2. Add the `-f` flag to `COMPOSE_F` in the Makefile:
   ```makefile
   COMPOSE_F := -f compose.yaml -f compose.portal-apme.yaml -f compose.portal-lightspeed.yaml
   ```
3. Update the EAP workflow to pull/save additional container images

## Relationship to Other Repos

| Repo | Role | Analogy |
|---|---|---|
| **automation-portal-local** (this repo) | Local compose wrapper over rhdh-local | Like `ansible-portal-chart` wraps `rhdh-chart` |
| [rhdh-local](https://github.com/redhat-developer/rhdh-local) | Base RHDH compose setup (submodule) | Like `redhat-developer-hub` Helm chart |
| [ansible-backstage-plugins](https://github.com/ansible/ansible-backstage-plugins) | Portal plugin source code | Plugin source |
| [ansible-rhdh-plugins](https://github.com/ansible-automation-platform/ansible-rhdh-plugins) | Plugin packaging + early-access CI | CI/CD for plugin tarballs + OCI images |
| [ansible-portal-chart](https://github.com/ansible-automation-platform/ansible-portal-chart) | Helm chart (OpenShift/K8s) | Production deployment |
| [apme](https://github.com/ansible/apme) | APME engine source + container images | Engine containers on ghcr.io |
