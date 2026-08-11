# Almost like AAP (`aap-mock`)

Stateful HTTP mock of AAP Gateway / Controller / OAuth for
[automation-portal-local](../README.md). Not a real Automation Controller.

## Login

Open the portal and sign in with **RHAAP**. You will land on the mock page titled
**Almost like AAP**. Credentials are prefilled; the form **auto-submits after 3
seconds**. Click **Cancel** (or focus/edit a field) to stop the countdown and
sign in manually.

| Field | Default |
|-------|---------|
| Username | `user` |
| Password | `password` |

Override with `AAP_MOCK_USERNAME` / `AAP_MOCK_PASSWORD`.

## Run standalone

```bash
npm install
npm start
# http://localhost:8099/health
# http://localhost:8099/o/authorize/
```

## Compose

Started automatically with `make dev` / `make start` when `AAP_MOCK=1`
(default in `.env.example`).

## Galaxy / Hub (on-demand + learned cache)

aap-mock does **not** index all of Galaxy. When a client asks for a named
collection (APME / `ansible-galaxy` via `/api/galaxy/content/...`, or search
with `namespace` + `name`), the mock resolves:

1. **certified** (console Hub, needs `AAP_MOCK_HUB_TOKEN`)
2. **validated** (console Hub, same token)
3. **galaxy** (`galaxy.ansible.com`, no token)

The first hit is cached. PAH catalog search returns **only the cache**, so the
portal collections UI grows as you pull collections — not ~4k Galaxy entries.

`AAP_MOCK_HUB_TOKEN` should be the **offline/refresh token** from
[console.redhat.com](https://console.redhat.com) Automation Hub → Connect (the
same token ansible-galaxy puts in `ansible.cfg` with `auth_url`). The mock
exchanges it at SSO for a Bearer access token before calling Hub. Sending the
offline token directly as `Authorization: Token …` will 401.

```bash
# Optional — enable certified/validated remotes
export AAP_MOCK_HUB_TOKEN=...   # also set in portal-local .env for compose

# Smoke (standalone mock)
npm start
curl -s -H "Authorization: Bearer local-mock-token" \
  'http://localhost:8099/api/galaxy/v3/plugin/ansible/search/collection-versions/?namespace=ansible&name=posix' | head
curl -s -H "Authorization: Bearer local-mock-token" \
  'http://localhost:8099/api/galaxy/v3/plugin/ansible/search/collection-versions/?namespace=redhat&name=rhel_system_roles' | head
curl -sI -H "Authorization: Token local-mock-token" \
  'http://localhost:8099/api/galaxy/content/published/collections/index/ansible/posix/'
```

Portal-local wires `pahCollections` + `portal_hub_*` bootstrap to this mock.
After an APME download, wait for the next PAH sync (or restart) to see the
collection in the UI.

## Tests

```bash
npm test
```
