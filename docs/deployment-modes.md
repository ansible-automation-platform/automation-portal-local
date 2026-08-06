# Deployment Modes

The portal supports three deployment modes controlled by environment variables in `.env`. Services are managed via compose profiles — disabled services don't start, pull images, or consume resources.

## Portal-only (IAG / customer delivery)

Minimal setup — just the portal and PostgreSQL. No APME plugins, no APME services.

```bash
AAP_MOCK=0
PORTAL_ONLY=1
```

**Containers:** `db`, `rhdh`, `install-dynamic-plugins`

Use this when delivering portal to customers who don't need APME quality scanning. Connect to a real AAP controller by setting `AAP_HOST_URL`, `AAP_PUBLIC_URL`, and OAuth credentials.

## Full stack (development)

Default mode — includes mock AAP server and APME quality scanning.

```bash
AAP_MOCK=1           # default
PORTAL_ONLY=0        # default
APME_EXTERNAL=0      # default
```

**Containers:** `db`, `rhdh`, `install-dynamic-plugins`, `aap-mock`, `apme-gateway`, `apme-primary` + validators, `apme-ui`

APME plugins are disabled by default in the overlay YAMLs. To enable them, set `disabled: false` on the APME entries in both `overlay/dynamic-plugins.portal.yaml` and `overlay/dynamic-plugins.portal.dev.yaml`. Running `make build-plugins` with APME in the PLUGINS list handles this automatically.

Use this for local development when you don't have access to a real AAP controller.

## External APME

APME plugins load but services run elsewhere (e.g. from the `apme` repo via `tox -e up`).

```bash
AAP_MOCK=1           # or 0 for real AAP
APME_EXTERNAL=1
APME_BASE_URL=http://host.containers.internal:8080   # default when external
```

**Containers:** `db`, `rhdh`, `install-dynamic-plugins`, `aap-mock` (if `AAP_MOCK=1`)

## How profiles work

| Variable | Profile | Services affected |
|---|---|---|
| `AAP_MOCK=0` | removes `mock` | `aap-mock` skipped |
| `PORTAL_ONLY=1` | removes `apme`, `apme-ui` | All `apme-*` containers skipped, APME plugins excluded |
| `APME_EXTERNAL=1` | removes `apme`, `apme-ui` | All `apme-*` containers skipped, APME plugins still load |
| `APME_UI=0` | removes `apme-ui` | Only `apme-ui` skipped (gateway + validators still run) |

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

When `APME_EXTERNAL=1`, all plugins (including APME) are included — they just point at an external Gateway via `APME_BASE_URL`.

Override with `PLUGINS="..."` on the command line if needed.
