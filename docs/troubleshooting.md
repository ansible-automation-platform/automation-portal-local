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

**Cause:** SELinux or rootless Podman user namespace mapping prevents the container (running as uid 1001) from writing to `dynamic-plugins-root`.

**Fix:**
```bash
make clean
chmod 777 rhdh-local/dynamic-plugins-root 2>/dev/null
make start SKIP_BUILD=1
```

### aap-mock container starts even with AAP_MOCK=0

**Cause:** The `.env` file was not read by compose. The `make start` target copies `.env` values to `rhdh-local/.env` during setup — running compose directly bypasses this.

**Fix:** Always use `make start` or `make dev`, not raw `podman compose up`.

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
