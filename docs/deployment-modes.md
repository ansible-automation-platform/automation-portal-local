# Deployment Modes

The portal supports two deployment modes controlled by environment variables in `.env`.
APME services are never bundled in compose — they run via `make apme` (`tox -e up` in `APME_REPO`).

## Portal-only (IAG / customer delivery)

Minimal setup — just the portal and PostgreSQL. No APME plugins; `make apme` is skipped.

```bash
AAP_MOCK=0
PORTAL_ONLY=1
```

**Containers:** `db`, `rhdh`, `install-dynamic-plugins`

Use this when delivering portal to customers who don't need APME quality scanning. Connect to a real AAP controller by setting `AAP_HOST_URL`, `AAP_PUBLIC_URL`, and OAuth credentials.

## Full stack (development)

Default mode — mock AAP server plus APME quality plugins pointed at a host Gateway.

```bash
AAP_MOCK=1           # default
PORTAL_ONLY=0        # default
# APME_REPO=$HOME/github/apme
# APME_BASE_URL=http://host.containers.internal:8080
```

**Portal containers:** `db`, `rhdh`, `install-dynamic-plugins`, `aap-mock`

**APME:** started by `make apme` (or automatically by `make dev` / `make start` when the default host Gateway is down):

```bash
make apme            # cd APME_REPO && tox -e up
make apme-down       # cd APME_REPO && tox -e down
```

Requires a local [apme](https://github.com/ansible/apme) clone and `tox` (`uv tool install tox --with tox-uv`). Abbenay / AI provider keys go in `APME_REPO/containers/abbenay/.env`.

### Upgrading from the old bundled compose APME stack

- Remove unused `.env` keys: `APME_EXTERNAL`, `APME_UI`, `APME_IMAGE_TAG`
- If `APME_BASE_URL` still points at `http://apme-gateway:8080`, unset it (Make rewrites to `host.containers.internal`)
- Move Abbenay keys from `.env-abbenay` → `APME_REPO/containers/abbenay/.env`
- `make start` / `make dev` remove leftover compose containers named `apme-gateway`, `apme-primary`, etc. (they do **not** touch the tox `apme-pod-*` containers)
- Old compose volumes (`apme-gateway-data`, `apme-sessions`) may remain; prune with `podman volume ls` / `podman volume rm` if desired
- `make stop` stops Portal only; use `make apme-down` for the APME pod

## How profiles work

| Variable | Profile | Services affected |
|---|---|---|
| `AAP_MOCK=0` | removes `mock` | `aap-mock` skipped |
| `PORTAL_ONLY=1` | — | APME plugins excluded; `make apme` skipped |

Profiles are resolved in the Makefile and exported as `COMPOSE_PROFILES`. You can inspect the active profiles with:

```bash
make status
```

## Plugin auto-selection

When `PORTAL_ONLY=1`, the default `PLUGINS` list excludes APME plugins (`backstage-apme`, `catalog-backend-module-apme`). Only the four portal-core plugins are built/exported:

- `auth-backend-module-rhaap-provider`
- `catalog-backend-module-rhaap`
- `self-service`
- `scaffolder-backend-module-backstage-rhaap`

Otherwise all plugins (including APME) are included and point at `APME_BASE_URL`.

Override with `PLUGINS="..."` on the command line if needed.

## Extensions catalog lab (`make extensions`)

RHDH 1.10 already ships the Extensions card catalog (Technology Preview) and
click-to-install (Developer Preview, `NODE_ENV=development` in rhdh-local).
Portal overlays keep those plugins **disabled**. This target turns them on
without loading APME from `PLUGIN_REPO`.

Do **not** commit a personal Quay namespace. Put image refs in gitignored `.env`
(or pass them on the command line). Shared/production images should live under
an org namespace (for example `quay.io/ansible/…`) once they exist.

| Piece | Source |
|---|---|
| RHDH | `RHDH_IMAGE` (default `quay.io/rhdh-community/rhdh:1.10`) |
| Portal plugins (auth, catalog-rhaap, self-service, scaffolder) | tarballs from `PLUGIN_REPO` (APME **branch** is fine) |
| APME plugins | **not** local `.tgz` — extra catalog index on Quay → `oci://` images |
| Primary plugin defaults | rhdh-local `CATALOG_INDEX_IMAGE` (`quay.io/rhdh/plugin-catalog-index:1.10.2`) |
| Extra index | `overlay/catalog-index/` (TechDocs, GitHub, APME). Catalog UI reads **only** this shelf (`/extensions/extra`), not the full official RHDH index. |

### What you must supply

Three **pushable** Quay image tags (replace `<ns>` with a namespace you can write):

| Variable | Image | What it is |
|---|---|---|
| `APME_FRONTEND_OCI` | `quay.io/<ns>/plugin-backstage-apme:<tag>` | APME frontend dynamic plugin OCI |
| `APME_BACKEND_OCI` | `quay.io/<ns>/plugin-catalog-backend-module-apme:<tag>` | APME catalog backend module OCI |
| `EXTENSIONS_CATALOG_INDEX` | `quay.io/<ns>/portal-plugin-catalog-index:<tag>` | Extra catalog **index** (Plugin YAML + package refs). Built by `make extensions-index`. |

Package the two APME plugins from `PLUGIN_REPO` **after** `dist-dynamic` exists
(export first, or reuse an export from `make start` / `make reload`). From each
plugin directory (not `dist-dynamic/`):

```bash
cd "$PLUGIN_REPO/plugins/backstage-apme"
npx @red-hat-developer-hub/cli@latest plugin package --tag quay.io/<ns>/plugin-backstage-apme:dev
podman push quay.io/<ns>/plugin-backstage-apme:dev

cd "$PLUGIN_REPO/plugins/catalog-backend-module-apme"
npx @red-hat-developer-hub/cli@latest plugin package --tag quay.io/<ns>/plugin-catalog-backend-module-apme:dev
podman push quay.io/<ns>/plugin-catalog-backend-module-apme:dev
```

`make extensions-index` appends these OCI layer names by default:

- frontend: `!ansible-plugin-backstage-apme`
- backend: `!ansible-backstage-plugin-catalog-backend-module-apme`

Override with `APME_FRONTEND_LAYER` / `APME_BACKEND_LAYER` if `plugin package`
printed different `oci://…!layer` paths.

Also required: `podman login quay.io` so both the host (index push) and the
installer (plugin/index pull) can reach private repos. Make copies host
registry auth from `~/.config/containers/auth.json` or
`$XDG_RUNTIME_DIR/containers/auth.json` into `rhdh-local/.registry/` (gitignored).

### Run the lab

```bash
# In .env (gitignored) or exported in the shell — never commit real tags:
EXTENSIONS_CATALOG_INDEX=quay.io/<ns>/portal-plugin-catalog-index:dev
APME_FRONTEND_OCI=quay.io/<ns>/plugin-backstage-apme:dev
APME_BACKEND_OCI=quay.io/<ns>/plugin-catalog-backend-module-apme:dev

podman login quay.io
make extensions-index
make extensions
```

Open http://localhost:7007/extensions/catalog (Administration → Extensions).
`/extensions` alone 404s.

After **Install** in the UI, run `make extensions` again (or `make stop` then
`make extensions`). Click-install state lives on the plugins volume;
`dynamic-plugins.extensions.yaml` is preserved. Use `SKIP_BUILD=1` to skip
rebuilding portal tarballs:

```bash
make extensions SKIP_BUILD=1
```

`make clean` is the wipe (volumes + click-install). A browser refresh is not
enough — the installer must run so APME OCI packages load. Missing
`pluginConfig` (`apmeApiFactory`, `gitRepositoriesExtensionsApiFactory`) is
filled from the extra catalog Package YAML.

`make extensions` is `PORTAL_ONLY=1`, so it does **not** start the Gateway.
Scans need `make apme`. Set **APME Gateway URL** in Quality settings to
`http://host.containers.internal:8080` (or `ansible.apme.baseUrl` /
`APME_BASE_URL`).

If the catalog still shows the full official RHDH shelf, wipe the Postgres
volume (`rhdh-local_portal-pgdata` or similar) so the provider re-ingests only
`/extensions/extra`.
