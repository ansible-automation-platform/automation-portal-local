# AGENTS.md — Automation Portal Local

Rules for AI agents and humans working in this repository.

## Dual compose modes

| Target | Config | Purpose |
|--------|--------|---------|
| `make dev` | `overlay/dynamic-plugins.portal.dev.yaml` | Edit plugin source; bind-mount `dist-dynamic` |
| `make start` | `overlay/dynamic-plugins.portal.yaml` | Production-shaped tarballs / EAP parity |
| `make extensions` | generated from `portal.yaml` | Portal-only + Extensions UI + extra Quay catalog index. Image tags live in gitignored `.env`; see `docs/deployment-modes.md`. Click-install is kept across `make extensions`; `make clean` wipes it. |

Both modes must load the same **host contract** for enabled plugins. Package paths differ (`.tgz` vs `local-plugins/portal-dev/…`); `pluginConfig` must not. APME plugins are optional — when disabled, the parity check skips them.

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

1. `overlay/dynamic-plugins.portal.dev.yaml`
2. `overlay/dynamic-plugins.portal.yaml`

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
- **APME Gateway** → not in compose; `make apme` runs `tox -e up` in `APME_REPO` (default `~/github/apme`). `make dev` / `make start` auto-start it when down; `PORTAL_ONLY=1` skips APME plugins and that step
- Exports are **incremental**: plugins with up-to-date `dist-dynamic` are skipped. Force everything with `FORCE_EXPORT=1`. Prefer `make reload PLUGINS=backstage-apme` or `make reload-fe` for UI-only work.
- Do not tell users to ignore `make start` when a story changes host registration — fix the overlay instead
- Never recommend `BUILD_TYPE=portal ./build.sh` against a developer clone — it deletes `plugins/backstage-rhaap`. Use `make build-plugins` / `make start` (export + pack) instead.

## Related repos

- Plugin source: `ansible-backstage-plugins` (`plugins/backstage-apme`, `plugins/self-service`, …)
- APME engine: `apme` — local pod via `make apme` (`tox -e up`); Abbenay keys in `APME_REPO/containers/abbenay/.env`
- When self-service gains a required `useApi(…ApiRef)`, the providing plugin’s factory **must** appear in both Portal overlays above
