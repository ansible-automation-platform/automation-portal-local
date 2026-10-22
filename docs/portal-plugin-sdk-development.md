# Developing Portal plugins and SDK with NFS

This developer procedure runs the Portal plugins and SDK from your active development checkout on `quay.io/rhdh-community/rhdh:next-2.1`. RHDH discovers the Portal host, self-service pages, and APME declarations through native frontend features. APME runs in its own Podman pod. The current `nfs-dev` configuration uses mock AAP authentication; it is not a real-AAP deployment procedure.

## SDK development scope

The plugin repository owns the Portal SDK implementation: shared manifest and launch contracts, native contribution Blueprints, host validation/rendering, frontend components and context helpers, backend operation/entitlement services, audit helpers, and push-based health aggregation. NFS is the composition and loading path for those frontend contributions, not the entire SDK feature.

Automation-portal-local supplies deployment overlays, exports, installation, configuration parity checks, and the local RHDH test environment. It does not replace the SDK implementation or require contributors to use a particular fork.

SDK libraries are not separate dynamic page plugins. Their changes are consumed through the exported host and contributor packages. Rebuild and verify those consumers together after changing shared contracts or implementations.

## Prerequisites

- Your plugin repository checkout contains the Portal SDK and native NFS changes on the branch you are developing. It can be an upstream checkout or a fork; no particular remote is required.
- The automation-portal-local checkout includes `scripts/start-nfs.sh`, `scripts/prepare-nfs.mjs`, and `scripts/refresh-nfs-cache.mjs`, plus initialized `rhdh-local` submodules.
- Node.js 22 and Corepack/Yarn 4 are available in the plugin checkout, and plugin dependencies are installed.
- Podman Compose is available. Your APME checkout has its documented `tox -e up` prerequisites and enough resources for the full stack.
- GitHub integration credentials are configured locally if you intend to register or read GitHub repositories. Do not commit `.env` or credentials.

## Configuring the local checkouts

1. In your existing plugin checkout, verify the branch without discarding uncommitted work:

   ```bash
   cd /path/to/plugin-repository
   git branch --show-current
   ```

   The output should be `main` or your development branch containing the changes to test. No fixed integration branch is required.

   To change branches, first inspect `git status --short` and preserve any local work. Then select your branch:

   ```bash
   portal_development_branch="<development-branch>"
   git switch "$portal_development_branch"
   ```

   Replace `<development-branch>` with an existing local branch name. This guide does not require rebasing, pulling, or discarding changes.

2. In automation-portal-local, initialize the submodule when needed:

   ```bash
   cd /path/to/automation-portal-local
   git submodule update --init --recursive
   ```

3. Create `.env` from `.env.example` only if it does not already exist. Preserve existing credentials and other overrides. Set these fields:

   ```dotenv
   PLUGIN_REPO=/path/to/plugin-repository
   APME_REPO=/path/to/apme
   PORTAL_ONLY=0
   AAP_MOCK=1
   RHDH_IMAGE=quay.io/rhdh-community/rhdh:next-2.1
   ```

   These are the minimal checkout/image settings for the full-stack native development path; retain the remaining required values from `.env.example`.

## Starting the stack

1. For a selection containing APME, start it through its supported orchestration if it is not already running:

   ```bash
   cd /path/to/automation-portal-local
   make apme
   ```

   This runs `tox -e up` in `APME_REPO`. `make nfs-dev` does not start the APME pod itself.

2. Start or update native RHDH:

   ```bash
   make nfs-dev
   ```

   By default, the script exports 12 Portal frontend/backend packages from the workspace checkout, generates native deployment overlays, installs them alongside stock RBAC, and refreshes mutable Module Federation metadata timestamps. It recreates only this checkout's RHDH and one-shot installer containers. The stateless AAP mock can be recreated to pick up OAuth configuration; PostgreSQL, database volumes, and the separate APME pod are preserved. Stock OCI resolution can take several minutes.

3. Open `http://localhost:7007` and select AAP sign-in. The generated NFS overlay uses the mock provider. No `portalFrontend=nfs` query parameter is required in RHDH.

## Selecting development plugins

These presets test optional composition; they are not production configuration,
permissions, or SDK restrictions. Production installations select dynamic
artifacts normally. For source-app presets and `app.packages.include`, use the
plugin repository's root README, not a production configuration guide.

- `PORTAL_PROFILE=full` is the default: 12 Portal packages, including
  portal-scaffolder and APME.
- `PORTAL_PROFILE=scaffolder` selects nine packages and omits APME.
- `PORTAL_PROFILE=core` selects seven packages and omits both contributors.
  Authentication and core services remain. Content pages still live in
  portal-scaffolder, so they are absent in this selection.
- `PORTAL_ONLY=1` remains shorthand for the scaffolder preset when no profile
  is supplied. An explicit `full` conflicts with that flag; use `PORTAL_ONLY=0`
  when selecting full explicitly.

### Preparing and starting a selection

Prerequisites: install dependencies in `PLUGIN_REPO`; use the development
checkout containing the workspace-selection helper and native export scripts.

1. Generate/export and check contracts without changing services:

   ```bash
   PORTAL_PROFILE=core PORTAL_ONLY=0 NFS_PREPARE_ONLY=1 make nfs-dev
   ```

2. Start that selection after successful preparation:

   ```bash
   PORTAL_PROFILE=core PORTAL_ONLY=0 SKIP_EXPORT=1 make nfs-dev
   ```

3. Check readiness and verify that omitted contributors are absent from both
   the installed artifacts and UI, rather than only hidden from navigation.
   Without an installed landing destination, `/` shows the neutral host page.
   Use the same selection variables when running parity, packing, or cache
   refresh commands.

Each preset has a separate installation root; workspace and packed modes are
also isolated. Additional package selections add a stable selection fingerprint
to those paths. Switching selections does not delete previous roots or volumes.
Configured navigation and entitlement policy are preserved; presets do not
grant access. Backend health alone does not prove page permissions or logout.

### Adding other workspace plugins

Register packages in `PLUGIN_REPO` under `workspaces/<workspace>/plugins/<name>`.
Select package names, not directory paths or URLs:

```bash
PORTAL_PROFILE=core PORTAL_ONLY=0 \
PORTAL_EXTRA_PLUGINS='@ansible/plugin-example,@ansible/plugin-example-backend' \
NFS_PREPARE_ONLY=1 make nfs-dev
```

The same selection drives export, workspace overlays, packed overlays, parity,
and installation. Replace the example names with real workspace packages;
then omit `NFS_PREPARE_ONLY=1` to start them. An extra package needs a frontend
or backend plugin/module Backstage role and an `export-dynamic` script using
the RHDH CLI. Frontend packages also need a native `./alpha` export. SDK
libraries are bundled dependencies, not standalone plugin selections. Shared
artifact directory basenames must be unique. APME's current frontend still
requires portal-scaffolder's repository pages.

`PORTAL_EXTRA_PLUGINS` accepts comma- or whitespace-separated names. It does not
require editing the preset inventory or publishing to npm. Unlike installation
selection, `EXPORT_PLUGINS` only limits incremental rebuilds: it never adds or
removes installed plugins. Keep all selected exports current after SDK changes.

## Validating SDK changes

### Prerequisites

- The plugin checkout is on the branch containing the changes to verify.
- Dependencies are installed for that checkout.
- The local RHDH/APME configuration above is available for integration checks.

### Procedure

1. Validate source changes in the plugin repository:

   ```bash
   cd /path/to/plugin-repository
   yarn tsc
   yarn lint:all
   yarn test
   yarn test:composition
   ```

   These checks cover the SDK and its consumers; successful dynamic discovery
   alone does not prove operation authorization or backend behavior.

   In automation-portal-local, validate selection, generated overlays, and
   bounded startup behavior with temporary command doubles:

   ```bash
   PLUGIN_REPO=/path/to/plugin-repository node --test scripts/nfs-composition.test.mjs
   ```

   These tests do not replace live RHDH or real-AAP acceptance.

2. Re-export the full installed package set after shared SDK, contract, or
   dependency changes:

   ```bash
   cd /path/to/automation-portal-local
   make nfs-dev
   ```

   Do not use `SKIP_EXPORT=1` after a branch switch or SDK change unless every
   affected export has already been rebuilt. Limit `EXPORT_PLUGINS` only when
   you know which host/contributor packages consume the changed code.

### Verification

Use the UI and parity checks below for native contributions. For backend SDK
changes, verify the affected registered operation's authorization, current
subject, organization, and entitlement behavior. Check backend health through
`/api/portal-health/status`; this is a backend aggregator, not a new UI page.

See the plugin checkout's `docs/next/portal-plugin-factory-implementation-guide.md`
and `docs/next/portal-sdk-nfs-composition.md` for the current contract and
remaining architecture work. This runbook does not claim content extraction
or full multi-organization session support is complete.

## Refreshing changed plugins

For frontend host or contribution changes, refresh the paired host/contributor builds:

```bash
cd /path/to/automation-portal-local
EXPORT_PLUGINS='portal-core portal-scaffolder backstage-apme' make nfs-dev
```

For a navigation-only change:

```bash
EXPORT_PLUGINS='portal-core' make nfs-dev
```

Only skip exports when all installed `dist-dynamic` artifacts are current:

```bash
SKIP_EXPORT=1 make nfs-dev
```

To install packed exports instead of workspace directories on the same image:

```bash
SKIP_EXPORT=1 NFS_PACKAGE_MODE=packed make nfs-dev
```

This packs current exports into `local-plugins/portal-nfs` and uses the separate `rhdh-local/dynamic-plugins-root-nfs-packed` installation directory. It does not delete legacy archives or database volumes. Return to workspace mode with `SKIP_EXPORT=1 make nfs-dev` (omit `NFS_PACKAGE_MODE=packed`).

Use the native script rather than assuming legacy `make dev`, `make reload`, or `make start` select the native overlays.

## Sidebar configuration

`scripts/prepare-nfs.mjs` owns the generated `overlay/app-config.portal.nfs.yaml`. Edit the generator rather than a generated file that will be overwritten on the next start.

The complete navigation override is:

```yaml
app:
  extensions:
    - nav-content:app/sidebar: false
    - nav-content:app/portal: true
portal:
  navigation:
    topOffset: 64
    items:
      - id: templates
        path: /self-service
        title: Templates
      - id: history
        path: /self-service/create/tasks
        title: History
      - id: execution-environments
        path: /self-service/ee
        title: Execution Environments
      - id: collections
        path: /self-service/collections
        title: Collections
      - id: repositories
        path: /self-service/repositories
        title: Git repositories
      - id: administration
        title: Administration
        placement: bottom
        children:
          - id: rbac
            path: /rbac
            title: RBAC
      - id: settings
        path: /settings
        title: Settings
        placement: bottom
```

Disabling the stock attachment is necessary because the native navigation content input accepts one component. The top offset reserves space for RHDH's fixed header. Without a landing override, the app root redirects to Templates only when installed; otherwise it shows the neutral host fallback. The host selects discovered navigation items by exact route or page extension ID in configured order; it does not invent missing entries or grant permissions. Unlisted routes and their APIs remain installed. The duplicate `/portal/catalog`, `/portal/entity/...`, and `/portal/start` routes are removed, not merely hidden.

For a minimal direct Administration link, use:

```yaml
portal:
  navigation:
    items:
      - id: administration
        path: /rbac
        title: Administration
        placement: bottom
```

To switch a group to a direct link, remove `children` and supply exactly one `path` or `page` selector. Groups require a title and child links; they cannot also specify a route. Missing child pages are omitted, and empty groups are hidden. IDs and route targets must be unique. The older `paths` and `bottomPaths` settings remain a fallback only when `items` is absent. Icons come from native page declarations; the restored self-service icons match the legacy sidebar. Group icons currently inherit the first available child icon, and icon overrides are not a navigation config field.

## Verification

1. Check RHDH readiness:

   ```bash
   curl -fsS http://localhost:7007/healthcheck
   ```

   Expected: HTTP 200 after initialization.

2. Verify the dev/tarball configuration contract:

   ```bash
   PLUGIN_REPO=/path/to/plugin-repository node scripts/check-nfs-parity.mjs
   ```

   Expected: the selected profile's dev/tarball contracts match (12 Portal packages plus stock RBAC for the default full selection).

3. After sign-in, verify the sidebar order is Templates, History, Execution Environments, Collections, Git repositories, then Administration and Settings at the bottom. Administration expands to show RBAC; Settings remains separate. Verify the old `/portal` routes show the standard not-found page and the header logo leads to Templates.
4. Open the repository catalog and verify Add repository, Quality, Quality settings, and Violations. Open a supported repository to verify Quality, Quality activity, Dependencies, and the overview card.
5. Inspect a registration workflow without submitting it unless you intend to create Catalog data. Verify both `/self-service/create/tasks` and task-detail routes.

## Removal behavior

Confirmed deregistration removes a manually registered Catalog entry, not the underlying Git repository or APME project/history. Catalog cleanup is asynchronous. The native action retries Catalog reads before refreshing the list or leaving the entity page. If cleanup remains pending or the verification read fails, Check catalog removal repeats only the reads; it does not resubmit the mutation. Do not treat a permissions or transport error as confirmed absence.

## Troubleshooting

**App startup reports multiple navigation content attachments**

Enable only the Portal navigation attachment and disable `nav-content:app/sidebar`, as shown above. Regenerate the overlay and restart RHDH.

**The first sidebar link is hidden or clicks the header logo**

Set the fixed-header clearance with `portal.navigation.topOffset: 64` in the local generator. Other hosts without a fixed header can omit it.

**A new native bundle fails despite a successful export**

Inspect `/tmp/anstrat-rhdh-export-<plugin>.log` and the installer:

```bash
podman logs --tail 80 rhdh-plugins-installer
```

Re-export the host and contributor together. Reproducible installer timestamps can produce stale weak ETags for same-sized Module Federation metadata. The native start script runs `scripts/refresh-nfs-cache.mjs`; use that existing cache-validator step rather than clearing data volumes.

**RHDH restart fails because its installer dependency is stopped**

Podman Compose retains the one-shot installer as a runtime dependency. The native script validates container ownership, recreates only this checkout's app/installer runtime containers, waits for a successful installer exit, refreshes metadata, and starts RHDH. It refuses containers owned by another checkout. Verify health and the displayed navigation rather than relying on export success.

**Configured navigation is empty**

Nested navigation configuration must be frontend-visible. The host schema uses `@deepVisibility frontend` for `portal.navigation.items`. Re-export portal-core after a schema change, and restart the source dev server after changing config or schemas. A browser refresh alone does not reload the dev server's cached configuration.

**APME scan submission succeeds but no assessment completes**

Inspect APME engine/dependency logs. The previously observed scan aborted on unavailable collection dependencies. That is distinct from native discovery or operation submission. The current mock Galaxy HTTP URL is also incompatible with the gateway's HTTPS-only server validation; do not disable that validation to make acceptance pass.

## Scope and safety

Validation targets `next-2.1` only. Its packed deployment was exercised with mock AAP authentication, native registration/deregistration and existing APME project preservation. Separately, the source NFS app was exercised with real AAP login and completed scan-only operations on the existing `my-ns-my-col` test repository. Its persisted scan count increased from two to four with one finding, and the selected Quality summary refreshed automatically. No remediation, branch, or PR was applied. This is not evidence of real-AAP authentication in the RHDH container or a successful scan of every repository.

Content extraction/query/write/picker migration is not delivered by NFS composition. The source development app defaults to NFS and retains `?portalFrontend=legacy` as an explicit fallback; that selector does not apply to the RHDH container's app shell.

Keep services running for manual verification. Do not use `make clean`, volume deletion, or APME wipe commands as a refresh mechanism.
