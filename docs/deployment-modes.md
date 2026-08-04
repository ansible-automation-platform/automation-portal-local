# Deployment Modes

The portal supports three deployment modes controlled by environment variables in `.env`. Services are managed via compose profiles — disabled services don't start, pull images, or consume resources.

## Portal-only (EAP / customer testing)

Minimal setup — just the portal and PostgreSQL. No mock server, no APME.

```bash
AAP_MOCK=0
APME_EXTERNAL=1
```

**Containers:** `db`, `rhdh`, `install-dynamic-plugins`

Use this when connecting to a real AAP controller for EAP testing.

## Full stack (development)

Default mode — includes mock AAP server and APME quality scanning.

```bash
AAP_MOCK=1           # default
APME_EXTERNAL=0      # default
```

**Containers:** `db`, `rhdh`, `install-dynamic-plugins`, `aap-mock`, `apme-gateway`, `apme-primary` + validators, `apme-ui`

Use this for local development when you don't have access to a real AAP controller.

## External APME

Portal + mock AAP, but pointing at an APME gateway you run separately (e.g. from the `apme` repo via `tox -e up`).

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
| `APME_EXTERNAL=1` | removes `apme`, `apme-ui` | All `apme-*` containers skipped |
| `APME_UI=0` | removes `apme-ui` | Only `apme-ui` skipped (gateway + validators still run) |

Profiles are resolved in the Makefile and exported as `COMPOSE_PROFILES`. You can inspect the active profiles with:

```bash
make status
```

## Plugin auto-selection

When `APME_EXTERNAL=1`, the default `PLUGINS` list automatically excludes APME plugins (`backstage-apme`, `catalog-backend-module-apme`). Only the four portal-core plugins are built/exported:

- `auth-backend-module-rhaap-provider`
- `catalog-backend-module-rhaap`
- `self-service`
- `scaffolder-backend-module-backstage-rhaap`

Override with `PLUGINS="..."` on the command line if needed.
