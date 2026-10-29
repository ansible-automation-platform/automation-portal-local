# Developing Portal plugins and SDK with NFS

This developer procedure runs the Portal plugins and SDK from your active development checkout on `quay.io/rhdh-community/rhdh:next-2.1`. RHDH discovers the Portal host, portal-scaffolder pages, and APME declarations through native frontend features. APME runs in its own Podman pod. The `nfs-dev` workflow defaults to mock AAP authentication and supports an existing real AAP deployment with `AAP_MOCK=0`.

## SDK development scope

The plugin repository owns the Portal SDK implementation: shared manifest and launch contracts, native contribution Blueprints, host validation/rendering, frontend components and context helpers, backend operation/entitlement services, audit helpers, and push-based health aggregation. NFS is the composition and loading path for those frontend contributions, not the entire SDK feature.

Automation-portal-local supplies deployment overlays, exports, installation, configuration parity checks, and the local RHDH test environment. It does not replace the SDK implementation or require contributors to use a particular fork.

SDK libraries are not separate dynamic page plugins. Their changes are consumed through the exported host and contributor packages. Rebuild and verify those consumers together after changing shared contracts or implementations.

## Prerequisites

- Your plugin repository checkout contains the Portal SDK, the `portal-rhdh` profile adapter, AAP OIDC logout, and the renamed `workspaces/portal-scaffolder` workspace. It can be an upstream checkout or a fork. Before [PR #954](https://github.com/ansible/ansible-backstage-plugins/pull/954) merges, use its branch for the profile/logout changes. After it merges, an updated `main` is sufficient.
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

   These are the minimal checkout/image settings for the full-stack mock development path. Retain the remaining required values from `.env.example`. To use your existing AAP deployment, follow the real-AAP procedure below.

## Configuring real AAP

### Prerequisites

- Your AAP deployment advertises `/o/logout/` as its OIDC end-session endpoint.
- You have a registered Portal OAuth application and its client ID, client secret, and catalog API token.
- The AAP API is reachable from the RHDH container and any APME pod. Its public URL is reachable from your browser.

### Procedure

1. Update the existing `.env` with your AAP values. Preserve unrelated credentials.

   ```dotenv
   AAP_MOCK=0
   AAP_HOST_URL=https://aap.example.com
   AAP_PUBLIC_URL=https://aap.example.com
   AAP_TOKEN=<catalog-api-token>
   OAUTH_CLIENT_ID=<portal-client-id>
   OAUTH_CLIENT_SECRET=<portal-client-secret>
   ```

   Use a container-reachable `AAP_HOST_URL` and browser-facing `AAP_PUBLIC_URL`.
   They can differ. The generator retains the provider settings and organization
   policy from `overlay/app-config.portal.yaml`. It defaults an absent provider
   `tokenHost` to `${AAP_HOST_URL}`. An explicitly configured `tokenHost` is retained.
   Credentials remain environment references in the generated YAML.

2. In the same AAP OAuth application, register the redirect URI
   `http://localhost:7007/api/auth/rhaap/handler/frame`. Register
   `http://localhost:7007/` under **Post Logout Redirect URIs**.

   The logout URI must exactly match the serialized Portal base URL
   (`new URL(appBaseUrl).href`). The default RHDH `BASE_URL` is
   `http://localhost:7007`, which serializes with the trailing slash. If you
   change `BASE_URL` or override `app.baseUrl`, update both registrations.
   For a separately running source app, register its configured backend callback
   and its post-logout URI `http://localhost:3000/` in the matching application.

3. Prepare the artifacts and configuration before changing running services:

   ```bash
   NFS_PREPARE_ONLY=1 make nfs-dev
   ```

4. Start APME with `make apme` if your selected preset includes it, then start RHDH:

   ```bash
   SKIP_EXPORT=1 make nfs-dev
   ```

   For packed artifacts, use `NFS_PACKAGE_MODE=packed` in both commands.
   Real-AAP mode does not start or recreate `aap-mock`. An existing mock
   container is left untouched. PostgreSQL volumes and the APME pod are preserved.

### Verification

Sign in at `http://localhost:7007` using AAP. Open the account menu and verify
one **Sign out** item. Select it, confirm logout in AAP, and verify that AAP
returns you to Portal sign-in. Cancelling the confirmation leaves the AAP
browser session active even though Portal auth is cleared. This manual check
is required for your AAP instance. Automated configuration tests do not prove
that its redirect registrations or token revocation work.

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

   By default, the script exports 13 Portal frontend/backend packages from the workspace checkout, generates native deployment overlays, installs them alongside stock RBAC, and refreshes mutable Module Federation metadata timestamps. This includes the optional `portal-rhdh` native header adapter. It recreates only this checkout's RHDH and one-shot installer containers. In mock mode, the stateless AAP mock can be recreated to pick up OAuth configuration. PostgreSQL, database volumes, and the separate APME pod are preserved. Stock OCI resolution can take several minutes.

3. Open `http://localhost:7007` and select AAP sign-in. The generated NFS overlay uses your selected mock or real AAP provider. No `portalFrontend=nfs` query parameter is required in RHDH.

## Selecting development plugins

These presets test optional composition; they are not production configuration,
permissions, or SDK restrictions. Production installations select dynamic
artifacts normally. For source-app presets and `app.packages.include`, use the
plugin repository's root README, not a production configuration guide.

- `PORTAL_PROFILE=full` is the default: 13 Portal packages, including
  portal-scaffolder and APME.
- `PORTAL_PROFILE=scaffolder` selects ten packages and omits APME.
- `PORTAL_PROFILE=core` selects eight packages and omits both contributors.
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

### Native header integration

All three local selections install `@ansible/portal-rhdh` for profile-menu
contributions. The global Create button is removed. Page-specific actions stay
with their owning page and do not use a global Create contribution API.

For real AAP (`AAP_MOCK=0`), the generator applies these native extension settings:

```yaml
app:
  extensions:
    - gh-component:global-header/self-service-button: false
    - gh-menu-item:global-header/logout: false
    - app-profile-menu-item:app/aap-logout: true
```

AAP logout is opt-in in the AAP auth module. Mock mode instead enables stock
`gh-menu-item:global-header/logout` and disables the AAP contribution because
the mock has no OIDC end-session endpoint. Stock logout clears Portal auth.
The global Create button is disabled in both modes. The source app uses its
own header and does not install this RHDH-specific adapter.

The generic `gh-menu-item:portal-rhdh/profile` attachment renders accepted
`AppProfileMenuItemBlueprint` navigation and lazy UI actions. New plugin items
require no edits to the adapter. Profile actions declare either authenticated
UI access or a required permission; backend mutations still use registered
operations. The host checks visibility before loading action code and isolates
failures from sibling items.

Enable the AAP-owned `app-profile-menu-item:app/aap-logout` entry above and rebuild
the host, adapter, and auth artifacts together. `portal-rhdh` has no AAP dependency.
Keep stock logout when not opting in to AAP logout. The source app uses its own
generic profile renderer and explicitly installs the AAP profile declaration.
For real AAP logout, the deployment must advertise `/o/logout/` as its OIDC
end-session endpoint. Register the serialized Portal `app.baseUrl`
(`new URL(appBaseUrl).href`) in the OAuth application's **Post Logout Redirect
URIs**: `http://localhost:7007/` for RHDH,
and `http://localhost:3000/` for the source app. The field accepts space-separated
URLs. Keep the configured OAuth environment's public `host` and `clientId`
aligned with that application; the private token host and client secret are not
exposed by the frontend auth schema. Restart/re-export after schema changes.
Sign out clears Portal auth, opens AAP's confirmation screen, and returns to
Portal sign-in after confirmation. Cancelling does not end the AAP browser
session. The mock-backed preset does not certify this real-AAP flow. Neither
the SDK nor this harness modifies gateway-wide logout allowlists.

### Sidebar layout

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

   Expected: the selected profile's dev/tarball contracts match (13 Portal packages plus stock RBAC for the default full selection).

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

Validation targets `next-2.1` only. Earlier packed content checks used mock AAP authentication, native registration/deregistration and existing APME project preservation. Separately, the source NFS app was exercised with real AAP login and completed scan-only operations on the existing `my-ns-my-col` test repository. Its persisted scan count increased from two to four with one finding, and the selected Quality summary refreshed automatically. No remediation, branch, or PR was applied.

Earlier manual real-AAP overrides exercised sign-in and a single native Sign out item before this generator support was added. The current profile-only header and generated real-AAP mode require fresh live acceptance. Configuration and startup regression tests run without contacting AAP or changing containers. Intermittent token-exchange/revocation transport errors were observed in earlier checks. A browser redirect alone is not proof that server-side revocation succeeded. These checks are not evidence of a successful scan of every repository.

Content extraction/query/write/picker migration is not delivered by NFS composition. The source development app defaults to NFS and retains `?portalFrontend=legacy` as an explicit fallback; that selector does not apply to the RHDH container's app shell.

Keep services running for manual verification. Do not use `make clean`, volume deletion, or APME wipe commands as a refresh mechanism.
