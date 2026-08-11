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
