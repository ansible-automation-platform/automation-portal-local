# Automation Portal Local

Run the Automation Portal (RHDH + Portal plugins + APME) locally with Podman Compose.

This repository wraps [rhdh-local](https://github.com/redhat-developer/rhdh-local) as a git submodule and adds Portal + APME configuration overlays, scripts, and an EAP distribution workflow. It uses RHDH's [dynamic plugin loading](https://docs.redhat.com/en/documentation/red_hat_developer_hub/) — the same mechanism used in production — so local testing matches the deployed experience.

## Quick Start (Developer)

```bash
# 1. Clone with submodules
git clone --recurse-submodules <repo-url>
cd automation-portal-local

# 2. Set environment variables
cp .env.example .env
# Edit .env — fill in AAP_HOST_URL, AAP_TOKEN, OAUTH credentials, GITHUB_TOKEN

# 3. Build plugins from your local upstream clone (see "Getting Plugins" below)
./scripts/build-plugins.sh /path/to/ansible-backstage-plugins

# 4. Start
./scripts/start.sh
```

Portal UI: http://localhost:7007
APME Gateway: http://localhost:8080

## Prerequisites

- **Podman** 4.x+ with `podman compose`
- **git** (for submodule management)
- **Node.js** 22.x + Corepack (for building plugins locally)
- **8 GB+ RAM** (RHDH + 9 APME containers + PostgreSQL)

## Getting Plugins

Plugin tarballs go in `local-plugins/portal-apme/`. The plugins are loaded as RHDH dynamic plugins — the same mechanism used in production via the Helm chart. This means your local testing reflects exactly how the UI behaves in an OpenShift deployment.

There are two ways to get plugins:

### Option A: Build from local upstream clone (recommended for developers)

Use this when you are actively developing plugins and want to test your changes with dynamic plugin loading.

**Prerequisites:** You need a local clone of [ansible-backstage-plugins](https://github.com/ansible/ansible-backstage-plugins) with your feature branch checked out.

```bash
# Build from your local clone (uses whatever branch is checked out)
./scripts/build-plugins.sh /path/to/ansible-backstage-plugins

# Or specify a branch explicitly
./scripts/build-plugins.sh /path/to/ansible-backstage-plugins feat/apme-eap-next-ui-workflow
```

The build script delegates to the upstream repo's `build.sh` with `BUILD_TYPE=portal`, then packs each plugin's `dist-dynamic` output into `local-plugins/portal-apme/`. It also updates `overlay/dynamic-plugins.portal-apme.yaml` with the actual tarball filenames.

**What gets built (Portal mode):**

| Plugin | Package | Description |
|---|---|---|
| auth-backend-module-rhaap-provider | `ansible-backstage-plugin-auth-backend-module-rhaap-provider-dynamic-*.tgz` | AAP OAuth authentication |
| catalog-backend-module-rhaap | `ansible-backstage-plugin-catalog-backend-module-rhaap-dynamic-*.tgz` | AAP catalog sync (collections, templates, orgs) |
| self-service | `ansible-plugin-backstage-self-service-dynamic-*.tgz` | Portal frontend (landing page, routing, field extensions) |
| scaffolder-backend-module-backstage-rhaap | `ansible-plugin-scaffolder-backend-module-backstage-rhaap-dynamic-*.tgz` | Custom scaffolder actions |
| backstage-apme | `ansible-plugin-backstage-apme-dynamic-*.tgz` | APME frontend (Quality tab, scan workflow) |
| catalog-backend-module-apme | `ansible-backstage-plugin-catalog-backend-module-apme-dynamic-*.tgz` | APME backend (gateway proxy, catalog sync) |

**Development cycle:**
```bash
# 1. Make code changes in your ansible-backstage-plugins clone
# 2. Rebuild plugins
./scripts/build-plugins.sh /path/to/ansible-backstage-plugins

# 3. Restart to pick up new plugins
./scripts/stop.sh
./scripts/start.sh
```

### Option B: Download from GitHub Actions workflow (for PMs, QE, EAP)

Use this when you want pre-built plugins from a CI run — no local Node.js or build tools required.

**From ansible-rhdh-plugins early-access workflow:**

1. Go to [ansible-rhdh-plugins Actions](https://github.com/ansible-automation-platform/ansible-rhdh-plugins/actions/workflows/release-plugins.yaml)
2. Click **Run workflow** with:
   - `release_type`: `early-access`
   - `upstream_branch`: the branch to build from (e.g. `feat/apme-eap-next-ui-workflow`)
3. When complete, download the **plugin tarballs** artifact
4. Extract into `local-plugins/portal-apme/`:
   ```bash
   # The artifact contains a bundle tar.gz
   tar -xzf early-access-plugins-*.tar.gz -C local-plugins/portal-apme/
   ```
5. Update `overlay/dynamic-plugins.portal-apme.yaml` tarball filenames to match the downloaded versions. The `build-plugins.sh` script does this automatically for local builds, but for CI artifacts you need to update the filenames manually or re-run: `./scripts/build-plugins.sh` after placing tarballs.

**From automation-portal-local EAP workflow:**

1. Go to **Actions** > **EAP / Build Distributable** in this repo
2. Fill in inputs (see [EAP Distribution](#eap-distribution) below)
3. The workflow builds plugins, pulls APME images, and packages everything into a distributable tar

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `AAP_HOST_URL` | Yes | — | AAP controller URL (e.g. `https://aap.example.com`) |
| `AAP_TOKEN` | Yes | — | AAP API token |
| `OAUTH_CLIENT_ID` | Yes | — | RHAAP OAuth client ID |
| `OAUTH_CLIENT_SECRET` | Yes | — | RHAAP OAuth client secret |
| `GITHUB_TOKEN` | Yes | — | GitHub PAT for SCM integration |
| `GITHUB_OAUTH_CLIENT_ID` | No | — | GitHub OAuth app client ID |
| `GITHUB_OAUTH_CLIENT_SECRET` | No | — | GitHub OAuth app client secret |
| `GITLAB_TOKEN` | No | — | GitLab PAT (if using GitLab SCM) |
| `APME_IMAGE_TAG` | No | `latest` | APME container image tag from ghcr.io |
| `RHDH_IMAGE` | No | `quay.io/rhdh-community/rhdh:1.10` | RHDH base image |
| `CUSTOMER_SUPPORT_URL` | No | Red Hat support | URL for the Support button in the global header |
| `POSTGRES_PASSWORD` | No | `postgres` | PostgreSQL password |
| `NODE_TLS_REJECT_UNAUTHORIZED` | No | `0` | Set to `0` for self-signed certs |

## Scripts

| Script | Description |
|---|---|
| `./scripts/build-plugins.sh <path> [branch]` | Build dynamic plugin tarballs from a local upstream clone |
| `./scripts/start.sh` | Copy overlays into rhdh-local, load images if present, start all services |
| `./scripts/stop.sh` | Stop all services |
| `./scripts/cleanup.sh` | Stop services, remove volumes, clean copied overlay files |
| `./scripts/cleanup.sh --remove-images` | Full cleanup including container images |
| `./scripts/load-images.sh` | Load APME images from `images/*.tar.gz` archives |

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
./scripts/start.sh
```

### Customer cleanup

```bash
# Stop services
./scripts/stop.sh

# Full cleanup (removes volumes and data)
./scripts/cleanup.sh

# Full cleanup including container images
./scripts/cleanup.sh --remove-images
```

## Platform Notes

### macOS (Apple Silicon)

APME container images are published as `linux/amd64` only. On ARM hosts:
- `start.sh` auto-detects ARM and sets `APME_PLATFORM=linux/amd64` for Rosetta/QEMU emulation
- `start.sh` auto-sets `OPENSSL_CONF=/dev/null` to work around UBI10 FIPS provider failures under emulation
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
│  │              (REST API + gRPC Reporting)             │   │
│  └──────────────────────┬───────────────────────────────┘   │
│                         │                                   │
│                         ▼                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              apme-primary :50051                     │   │
│  │              (Orchestrator)                          │   │
│  │                                                      │   │
│  │  Shared network namespace (sidecar pattern):         │   │
│  │  ┌─────────┐ ┌─────┐ ┌─────────┐ ┌──────────┐       │   │
│  │  │ native  │ │ opa │ │ ansible │ │ gitleaks │       │   │
│  │  │ :50055  │ │:5054│ │ :50053  │ │ :50056   │       │   │
│  │  └─────────┘ └─────┘ └─────────┘ └──────────┘       │   │
│  │  ┌──────────────┐ ┌───────────┐ ┌──────────────┐    │   │
│  │  │ collection-  │ │ dep-audit │ │ galaxy-proxy │    │   │
│  │  │ health:50058 │ │ :50059    │ │ :8765        │    │   │
│  │  └──────────────┘ └───────────┘ └──────────────┘    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## How Dynamic Plugin Loading Works

This setup uses the same plugin loading mechanism as production:

1. Plugin tarballs (`.tgz`) are placed in `local-plugins/portal-apme/`
2. The `install-dynamic-plugins` init container runs `install-dynamic-plugins.sh` which extracts and installs them into a shared volume (`dynamic-plugins-root`)
3. The `rhdh` container starts with the installed plugins available at runtime
4. Plugin configuration (routes, mount points, field extensions) is defined in `dynamic-plugins.portal-apme.yaml`

This is identical to how the Helm chart ([ansible-portal-chart](https://github.com/ansible-automation-platform/ansible-portal-chart)) loads plugins in OpenShift — via tarball or OCI references in the `global.dynamic.plugins` values. Testing locally with this setup validates that your plugin changes will work correctly in production.

## Repository Structure

```
automation-portal-local/
├── .github/workflows/
│   ├── eap-build.yaml              # EAP distributable build workflow
│   └── update-submodule.yaml       # Weekly rhdh-local submodule update
├── rhdh-local/                     # git submodule (redhat-developer/rhdh-local)
├── overlay/
│   ├── compose.portal-apme.yaml           # Compose overlay (ghcr.io APME images)
│   ├── app-config.portal-apme.yaml        # Portal app-config
│   └── dynamic-plugins.portal-apme.yaml   # Plugin manifest
├── local-plugins/portal-apme/      # Plugin tarballs (gitignored)
├── scripts/
│   ├── build-plugins.sh            # Build plugins from local upstream clone
│   ├── start.sh                    # Assemble + compose up
│   ├── stop.sh                     # Compose down
│   ├── cleanup.sh                  # Full cleanup
│   └── load-images.sh             # Load APME OCI archives
├── .env.example                    # Environment variable template
└── README.md
```

## Adding More Integrations

The compose overlay pattern is extensible. To add another integration (e.g. Lightspeed):

1. Create a new compose overlay: `overlay/compose.portal-lightspeed.yaml`
2. Stack compose files in start.sh:
   ```bash
   podman compose -f compose.yaml -f compose.portal-apme.yaml -f compose.portal-lightspeed.yaml up -d
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
