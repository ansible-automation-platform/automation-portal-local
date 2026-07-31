# AGENTS.md — Automation Portal Local

Rules for AI agents and humans working in this repository.

## Dual compose modes

| Target | Config | Purpose |
|--------|--------|---------|
| `make dev` | `overlay/dynamic-plugins.portal-apme.dev.yaml` | Edit plugin source; bind-mount `dist-dynamic` |
| `make start` | `overlay/dynamic-plugins.portal-apme.yaml` | Production-shaped tarballs / EAP parity |

Both modes must load the same **host contract** for Portal + APME plugins. Package paths differ (`.tgz` vs `local-plugins/portal-apme-dev/…`); `pluginConfig` must not.

## Non-negotiable: host contract parity

RHDH does **not** auto-register frontend API factories from a plugin package. APME documents this in `createPlugin` — factories are registered only when listed under:

```yaml
pluginConfig:
  dynamicPlugins:
    frontend:
      ansible.plugin-backstage-apme:
        apiFactories:
          - importName: apmeApiFactory
          - importName: gitRepositoriesExtensionsApiFactory
```

**Any change** to host wiring — `apiFactories`, `dynamicRoutes`, `mountPoints`, `entityTabs`, `scaffolderFieldExtensions`, backend `pluginConfig` — must update **both**:

1. `overlay/dynamic-plugins.portal-apme.dev.yaml`
2. `overlay/dynamic-plugins.portal-apme.yaml`

in the **same change set**. Updating only DEV leaves `make start` broken (e.g. Git Repos `NotImplementedError` for `plugin.rhaap.git-repositories.extensions`).

### Definition of done for host-contract stories

- [ ] DEV YAML updated
- [ ] Tarball YAML updated (same importNames / paths / providers)
- [ ] `make check-plugin-parity` passes
- [ ] Smoke: Git Repos page loads under the mode you claim to support (`make start` and/or `make dev`)

## Enforcement

```bash
make check-plugin-parity
# or
python3 scripts/check-plugin-config-parity.py
```

CI runs this on every PR. Do not weaken the check to silence a failure — fix the tarball YAML.

## Daily development

- **Plugin feature work (fast loop)** → `make dev`, then use the interactive menu: **R** reload, **F** frontend, **S** stop (`make reload` / `make reload-fe` still work)
- **Production-shaped / tarball mode** → `make start` (exports + packs from `PLUGIN_REPO`, then compose up)
- **Pre-downloaded CI tarballs only** → `make start SKIP_BUILD=1`
- Exports are **incremental**: plugins with up-to-date `dist-dynamic` are skipped. Force everything with `FORCE_EXPORT=1`. Prefer `make reload PLUGINS=backstage-apme` or `make reload-fe` for UI-only work.
- Do not tell users to ignore `make start` when a story changes host registration — fix the overlay instead
- Never recommend `BUILD_TYPE=portal ./build.sh` against a developer clone — it deletes `plugins/backstage-rhaap`. Use `make build-plugins` / `make start` (export + pack) instead.

## Related repos

- Plugin source: `ansible-backstage-plugins` (`plugins/backstage-apme`, `plugins/self-service`, …)
- When self-service gains a required `useApi(…ApiRef)`, the providing plugin’s factory **must** appear in both Portal overlays above
