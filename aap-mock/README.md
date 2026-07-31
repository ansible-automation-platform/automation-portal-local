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

Started automatically with `./scripts/start-dev.sh` / `./scripts/start.sh` when
`AAP_MOCK=1` (default in `.env.example`).
