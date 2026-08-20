# Automation Portal Local

Run the Ansible Automation Portal (RHDH + Portal plugins) locally with Podman Compose.
Optionally includes a mock AAP server. APME runs from its own clone via `make apme`
(`tox -e up`) — this repo does not bundle the APME stack in compose.

This repository wraps [rhdh-local](https://github.com/redhat-developer/rhdh-local) as a git submodule and adds Portal configuration overlays, scripts, and an EAP distribution workflow. It uses RHDH's [dynamic plugin loading](https://docs.redhat.com/en/documentation/red_hat_developer_hub/) — the same mechanism used in production.

## Table of Contents

- [Customer Quick Start](#customer-quick-start)
- [Developer Quick Start](#developer-quick-start)
- [Deployment Modes](docs/deployment-modes.md) — portal-only vs full stack (external APME)
- [Customer Guide](docs/customer-guide.md) — multi-org config, plugin updates, EC2 setup
- [Troubleshooting](docs/troubleshooting.md) — OAuth, containers, plugins, networking
- [Prerequisites](#prerequisites)
- [Getting Plugins](#getting-plugins)
- [Environment Variables](#environment-variables)
- [Make Targets](#make-targets)
- [EAP Distribution](#eap-distribution)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Relationship to Other Repos](#relationship-to-other-repos)

## Customer Quick Start

For EAP customers testing portal features (e.g. multi-org) with a real AAP controller. See the full [Customer Guide](docs/customer-guide.md) for details.

```bash
# 1. Untar
tar xzf automation-portal-local-*.tar.gz && cd automation-portal-local

# 2. Configure
cp .env.example .env
# Edit .env — set AAP_HOST_URL, AAP_PUBLIC_URL, AAP_TOKEN, OAUTH_CLIENT_ID,
#              OAUTH_CLIENT_SECRET. Set AAP_MOCK=0 and PORTAL_ONLY=1.

# 3. Start
make start SKIP_BUILD=1
```

Portal UI: http://localhost:7007

**Updating plugins:** Copy new `.tgz` files to `local-plugins/portal/`, then `make stop && make start SKIP_BUILD=1`.

**Cleanup:** `make stop` or `make clean` (removes volumes).

## Developer Quick Start

Day-to-day plugin work mounts each plugin's `dist-dynamic` into RHDH. Uses the built-in mock AAP server by default. APME is started via `make apme` (`tox -e up` in your apme clone) — `make dev` does this automatically when the Gateway is down.

```bash
# 1. Clone with submodules
git clone --recurse-submodules <repo-url>
cd automation-portal-local

# 2. Set environment variables
cp .env.example .env
# Edit .env — set PLUGIN_REPO (plugins) and APME_REPO (default: ~/github/apme)

# 3. Start (exports dist-dynamic, ensures APME is up, mounts plugins, starts compose)
make dev
```

Portal UI: http://localhost:7007 — Login: Sign in with AAP → mock → `user` / `password`.

```bash
make reload                         # re-export changed plugins + restart rhdh
make reload PLUGINS=backstage-apme  # one plugin
make reload-fe                      # FE only (browser refresh, no restart)
make apme-down                      # stop the APME pod (Portal can keep running)
```

This is **not** webpack HMR — RHDH reloads mounted files on container restart. See [Deployment Modes](docs/deployment-modes.md).

## Prerequisites

- **Podman** 4.x+ with `podman compose` (or Docker 28.1.0+ with Compose)
- **8 GB+ RAM** (RHDH + PostgreSQL; more when APME is running via `make apme`)

For developers building plugins locally:

- **git** (for submodule management)
- **Node.js** 22.x + Corepack
- **APME clone** + **tox** (`uv tool install tox --with tox-uv`) when `PORTAL_ONLY!=1`

Customers using pre-built tarballs (`SKIP_BUILD=1`, `PORTAL_ONLY=1`) only need Podman.

## Getting Plugins

### Option A: Mount `dist-dynamic` (recommended for developers)

`make dev` runs `yarn export-dynamic` per plugin and bind-mounts `dist-dynamic` into RHDH.

```bash
make dev PLUGIN_REPO=/path/to/ansible-backstage-plugins
```

### Option B: Tarball pack (EAP / production-shaped)

`make start` builds plugin tarballs into `local-plugins/portal/`, then starts compose. Same install path as OpenShift.

```bash
make start PLUGIN_REPO=/path/to/ansible-backstage-plugins
```

Skip rebuild with pre-downloaded `.tgz`: `make start SKIP_BUILD=1`.

| Plugin | Package | Required |
|---|---|---|
| auth-backend-module-rhaap-provider | `ansible-backstage-plugin-auth-backend-module-rhaap-provider-dynamic-*.tgz` | Always |
| catalog-backend-module-rhaap | `ansible-backstage-plugin-catalog-backend-module-rhaap-dynamic-*.tgz` | Always |
| self-service | `ansible-plugin-backstage-self-service-dynamic-*.tgz` | Always |
| scaffolder-backend-module-backstage-rhaap | `ansible-plugin-scaffolder-backend-module-backstage-rhaap-dynamic-*.tgz` | Always |
| backstage-apme | `ansible-plugin-backstage-apme-dynamic-*.tgz` | APME only |
| catalog-backend-module-apme | `ansible-backstage-plugin-catalog-backend-module-apme-dynamic-*.tgz` | APME only |

### Option C: Download from GitHub Actions workflow

No local Node.js required. See [EAP Distribution](#eap-distribution).

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `AAP_HOST_URL` | Yes | — | AAP controller URL |
| `AAP_PUBLIC_URL` | No | same as `AAP_HOST_URL` | AAP URL reachable from browser (required when `AAP_MOCK=0`) |
| `AAP_TOKEN` | Yes | — | AAP API token |
| `OAUTH_CLIENT_ID` | Yes | — | RHAAP OAuth client ID |
| `OAUTH_CLIENT_SECRET` | Yes | — | RHAAP OAuth client secret |
| `AAP_MOCK` | No | `1` (on) | `0` disables mock AAP server |
| `PORTAL_ONLY` | No | `0` | `1` disables APME plugins and skips `make apme` (IAG delivery) |
| `PLUGIN_REPO` | Yes for `dev` | — | Path to ansible-backstage-plugins clone |
| `APME_REPO` | Yes when APME enabled | `$HOME/github/apme` | Path to apme clone (`make apme`) |
| `APME_BASE_URL` | No | `http://host.containers.internal:8080` | Gateway URL from RHDH (when `PORTAL_ONLY!=1`) |
| `RHDH_IMAGE` | No | `quay.io/rhdh-community/rhdh:1.10` | RHDH base image |
| `EXTENSIONS_CATALOG_INDEX` | `make extensions` | — | Extra catalog index image (`quay.io/<ns>/…`). Do not commit a personal namespace; see `docs/deployment-modes.md`. |
| `APME_FRONTEND_OCI` / `APME_BACKEND_OCI` | `make extensions-index` | — | Pushable APME plugin OCI tags substituted into the extra index |
| `NODE_TLS_REJECT_UNAUTHORIZED` | No | `0` | Set to `0` for self-signed AAP certs (dev only) |

See `.env.example` for the full list including GitHub/GitLab and database variables.

## Make Targets

| Target | Description |
|---|---|
| `make dev` | Dev loop: ensure APME + mount `dist-dynamic` + compose up |
| `make start` | Tarball mode: ensure APME + build `.tgz` + start (`SKIP_BUILD=1` to reuse) |
| `make extensions` | Portal-only + Extensions UI + extra Quay catalog index (no local APME plugins) |
| `make extensions-index` | Build/push the extra catalog index image to Quay |
| `make apme` | Start APME (`cd APME_REPO && tox -e up`) |
| `make apme-down` | Stop APME (`cd APME_REPO && tox -e down`) |
| `make stop` | Stop Portal compose services (APME keeps running) |
| `make reload` | Re-export changed plugins + restart rhdh |
| `make reload-fe` | FE-only refresh (no restart) |
| `make build-plugins` | Build plugin tarballs without starting |
| `make clean` | Stop + remove volumes |
| `make logs` | Follow compose logs |
| `make status` | Show running containers |

## EAP Distribution

Produce a self-contained tarball for customer delivery.

### Option 1: EAP workflow (recommended)

1. Go to **Actions** > **EAP / Build Distributable**
2. Set `upstream_branch` to the branch with your changes
3. Download the `automation-portal-local-*.tar.gz` artifact

### Option 2: Manual packaging

```bash
# Build plugins
cd /path/to/ansible-backstage-plugins && git checkout main
cd /path/to/automation-portal-local
make build-plugins PLUGIN_REPO=/path/to/ansible-backstage-plugins

# Verify (optional)
make start SKIP_BUILD=1 && make stop

# Package
cd /path/to
tar czf automation-portal-local-multiorg.tar.gz \
  --exclude='.git' --exclude='rhdh-local/.git' \
  --exclude='rhdh-local/dynamic-plugins-root' \
  --exclude='node_modules' --exclude='*.log' \
  automation-portal-local
```

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Podman Compose (this repo)                              │
│                                                          │
│  ┌──────────┐  ┌────────────────┐  ┌─────────────────┐  │
│  │ install- │  │      rhdh      │  │       db        │  │
│  │ dynamic- │→ │  (Portal UI)   │← │  (PostgreSQL)   │  │
│  │ plugins  │  │   :7007        │  │                 │  │
│  └──────────┘  └───────┬────────┘  └─────────────────┘  │
│                        │                                 │
│               ┌────────┴────────┐                        │
│               │  Optional mock  │                        │
│               ▼                 │                        │
│  ┌─────────────────┐            │                        │
│  │    aap-mock     │            │ host.containers.internal│
│  │  profile: mock  │            │                        │
│  │    :8099        │            │                        │
│  └─────────────────┘            │                        │
└─────────────────────────────────┼────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │  APME pod (make apme)   │
                    │  tox -e up in APME_REPO │
                    │  Gateway :8080          │
                    └─────────────────────────┘
```

## Repository Structure

```
automation-portal-local/
├── Makefile                          # Primary interface (make help)
├── docs/
│   ├── customer-guide.md             # Customer setup, multi-org, EC2
│   ├── deployment-modes.md           # Portal-only, full stack, profiles
│   └── troubleshooting.md            # Common issues and fixes
├── .github/workflows/
│   ├── eap-build.yaml                # EAP distributable build workflow
│   └── update-submodule.yaml         # Weekly rhdh-local submodule update
├── rhdh-local/                       # git submodule (redhat-developer/rhdh-local)
├── overlay/                          # Compose + config overlays
├── aap-mock/                         # Local AAP mock (profile: mock)
├── local-plugins/portal/             # Plugin tarballs (gitignored)
├── scripts/                          # Build, export, load helpers
├── .env.example
└── README.md
```

## Relationship to Other Repos

| Repo | Role |
|---|---|
| **automation-portal-local** (this repo) | Local compose wrapper over rhdh-local |
| [rhdh-local](https://github.com/redhat-developer/rhdh-local) | Base RHDH compose setup (submodule) |
| [ansible-backstage-plugins](https://github.com/ansible/ansible-backstage-plugins) | Portal plugin source code |
| [ansible-rhdh-plugins](https://github.com/ansible-automation-platform/ansible-rhdh-plugins) | Plugin packaging + early-access CI |
| [ansible-portal-chart](https://github.com/ansible-automation-platform/ansible-portal-chart) | Helm chart (OpenShift/K8s) |
| [apme](https://github.com/ansible/apme) | APME engine — local pod via `make apme` (`tox -e up`) |
