# Troubleshooting

Common issues and solutions when running Automation Portal Local.

## OAuth / Login

### "Auth provider registered for 'rhaap' is misconfigured"

**Cause:** The `AAP_PUBLIC_URL` environment variable is missing or not reaching the RHDH container.

**Fix:**
1. Ensure `AAP_PUBLIC_URL` is set in `.env` (not just `AAP_HOST_URL`)
2. `AAP_PUBLIC_URL` must be the AAP URL reachable from your browser
3. Restart with `make stop && make start SKIP_BUILD=1`

**Verify:** Check if the variable reached the container:
```bash
podman exec rhdh env | grep AAP_PUBLIC
```

### "Skipping rhaap auth provider, Missing required config"

**Cause:** The RHDH container started before the `.env` change was picked up. Compose caches environment from the first `up`.

**Fix:** Full restart (not just `restart`):
```bash
make stop
make start SKIP_BUILD=1
```

### OAuth redirect fails or loops

**Cause:** Mismatch between `AAP_PUBLIC_URL` and the OAuth application redirect URI configured on AAP.

**Fix:** The OAuth redirect URI on your AAP controller must be:
```
http://localhost:7007/api/auth/rhaap/handler/frame
```

If running on an EC2 instance, replace `localhost` with the instance's public IP or DNS.

## Container Issues

### "install-dynamic-plugins" exits with permission denied

**Cause:** On Fedora/RHEL with SELinux enforcing, bind-mounting `./dynamic-plugins-root` without `:Z` makes the directory invisible/unwritable inside the container (uid 1001). Rootless Podman user-namespace mapping can also block writes.

**Fix:** Ensure `compose.portal.dev.yaml` mounts use `:Z` (portal overlay does). Then:
```bash
chmod -R a+rwX rhdh-local/dynamic-plugins-root
# From rhdh-local, re-run installer then bring rhdh up:
podman compose -f compose.yaml -f compose.portal.yaml -f compose.portal.dev.yaml \
  -f compose.apme.dev.yaml run --rm --no-deps install-dynamic-plugins
podman compose -f compose.yaml -f compose.portal.yaml -f compose.portal.dev.yaml \
  -f compose.apme.dev.yaml up -d rhdh
```
Or `make clean && make dev DEV_PROMPT=0` for a full restart.

### `rhdh-plugins-installer` hangs at "Waiting for lock release"

**Cause:** A previous `make dev` was interrupted (Ctrl+C) while `install-dynamic-plugins` was running. The installer leaves `dynamic-plugins-root/install-dynamic-plugins.lock` behind; the next run waits on that file forever.

**Fix:** `make stop` then `make dev` again (recent Makefile clears the stale lock automatically). Manual:
```bash
rm -f rhdh-local/dynamic-plugins-root/install-dynamic-plugins.lock
podman compose -f rhdh-local/compose.yaml -f rhdh-local/compose.portal.yaml \
  -f rhdh-local/compose.portal.dev.yaml run --rm --no-deps install-dynamic-plugins
```

**Verify:** Installer logs should show `Created lock file` (not endless `Waiting for lock release`):
```bash
podman logs -f rhdh-plugins-installer
```

### aap-mock container starts even with AAP_MOCK=0

**Cause:** The `.env` file was not read by compose. The `make start` target copies `.env` values to `rhdh-local/.env` during setup — running compose directly bypasses this.

**Fix:** Always use `make start` or `make dev`, not raw `podman compose up`.

### Collections catalog empty / APME cannot download collections

**Cause:** aap-mock uses **on-demand resolve + learned cache**. The catalog only lists collections that have been pulled (or searched by `namespace`+`name`). It does not index all of Galaxy.

**Fix:**
1. Trigger a download through APME (or `curl` the content API for a known collection) so the mock caches it
2. Wait for the next `pahCollections` sync (or restart RHDH) to see it in the UI
3. For certified/validated content, set `AAP_MOCK_HUB_TOKEN` in `.env` to your
   console Hub **offline/refresh** token (Automation Hub → Connect). aap-mock
   SSO-exchanges it for a Bearer access token. If Hub still 401s, check
   `podman logs aap-mock` for `SSO token exchange failed`.

See `aap-mock/README.md` for smoke curls.

### "short-name did not resolve to an alias"

**Cause:** Podman's container registry configuration doesn't include a default search registry.

**Fix:** Add to `~/.config/containers/registries.conf`:
```toml
unqualified-search-registries = ["docker.io"]
```

## Plugin Issues

### No templates or users appear after login

**Cause:** AAP connection failed — either wrong credentials or network issue.

**Fix:**
1. Check logs: `make logs | grep -i error`
2. Verify `AAP_HOST_URL` and `AAP_TOKEN` in `.env`
3. If AAP uses self-signed certs, set `NODE_TLS_REJECT_UNAUTHORIZED=0` in `.env`
4. Ensure the AAP controller is reachable from the host running the portal

### Plugins not loading — "plugin not found" in logs

**Cause:** Plugin tarballs missing from `local-plugins/portal/`.

**Fix:**
```bash
ls local-plugins/portal/*.tgz
```

Expected files (4 for portal-only):
- `ansible-backstage-plugin-auth-backend-module-rhaap-provider-dynamic-*.tgz`
- `ansible-backstage-plugin-catalog-backend-module-rhaap-dynamic-*.tgz`
- `ansible-plugin-backstage-self-service-dynamic-*.tgz`
- `ansible-plugin-scaffolder-backend-module-backstage-rhaap-dynamic-*.tgz`

If missing, rebuild or obtain from the EAP workflow.

### Signals WebSocket error in logs

```
Failed to authenticate WebSocket connection: AuthenticationError: Failed user token verification
```

**This is expected** before any user logs in. The Backstage Signals plugin attempts a WebSocket connection on startup and retries after authentication. It self-recovers once a user signs in.

## Network / Firewall

### APME Quality features fail / Gateway unreachable

**Cause:** Portal expects APME at `APME_BASE_URL` (default `http://host.containers.internal:8080`). The Gateway is not running.

**Fix:**
```bash
make apme          # cd APME_REPO && tox -e up
# or ensure APME_REPO points at your apme clone
```

`make dev` / `make start` call this automatically when the Gateway does not respond. Abbenay / AI keys live in `APME_REPO/containers/abbenay/.env`, not in this repo.

### Portal not accessible from another machine

**Cause:** RHDH binds to `0.0.0.0:7007` inside the container, but the host firewall may block external access.

**Fix (Fedora/RHEL):**
```bash
sudo firewall-cmd --add-port=7007/tcp --permanent
sudo firewall-cmd --reload
```

**Fix (AWS EC2):** Add inbound rule for TCP port 7007 in the security group.

### Browser shows "SSL_ERROR_RX_RECORD_TOO_LONG"

**Cause:** Accessing `https://localhost:7007` but the portal runs on HTTP.

**Fix:** Use `http://localhost:7007` (no HTTPS). If the browser forces HTTPS (HSTS cached), use a private/incognito window.

## Parity Check

### "Plugin host-config parity check FAILED"

**Cause:** The DEV overlay (`dynamic-plugins.portal.dev.yaml`) and tarball overlay (`dynamic-plugins.portal.yaml`) have different enabled plugins.

**Fix:** Ensure both overlays have the same plugins enabled/disabled. The parity check only compares plugins that are enabled — disabled plugins in either file are ignored.

For portal-only mode, both APME plugins should be `disabled: true` in both overlays.
