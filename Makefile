# Automation Portal Local — Makefile
#
# Primary interface for the local Portal compose stack.
# APME runs via `make apme` (tox -e up in APME_REPO), not in compose.
# Run `make help` to see available targets.

.DEFAULT_GOAL := help
SHELL         := /bin/bash
.SHELLFLAGS   := -euo pipefail -c

ROOT_DIR  := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
RHDH_DIR  := $(ROOT_DIR)/rhdh-local
OVERLAY   := $(ROOT_DIR)/overlay

# ── Load .env (KEY=VALUE format; skipped if absent) ──────────────────
-include $(ROOT_DIR)/.env

# ── Defaults ─────────────────────────────────────────────────────────
PLUGIN_REPO   ?= $(HOME)/github/ansible-backstage-plugins
APME_REPO     ?= $(HOME)/github/apme
AAP_MOCK      ?= 1
PORTAL_ONLY   ?= 0
APME_BASE_URL ?=
# Set SKIP_BUILD=1 to use existing local-plugins/portal/*.tgz (CI artifacts).
SKIP_BUILD    ?= 0
# Set FORCE_EXPORT=1 to rebuild every plugin (ignore incremental dist-dynamic stamps).
FORCE_EXPORT  ?= 0
# Set DEV_PROMPT=0 to skip the interactive R/F/S menu after make dev.
DEV_PROMPT    ?= 1

# ── Compose-profile resolution ──────────────────────────────────────
# Profiles: mock (aap-mock). APME is external (make apme → tox -e up).
_PROFILES :=

# AAP mock server: enabled by default, disabled with AAP_MOCK=0
_MOCK := $(shell echo '$(AAP_MOCK)' | tr '[:upper:]' '[:lower:]')
ifneq ($(filter 0 false no off,$(_MOCK)),)
  # Real AAP — no mock
else
  _PROFILES += mock
endif

# APME Gateway URL (plugins still load unless PORTAL_ONLY=1)
_PORTAL_ONLY := $(shell echo '$(PORTAL_ONLY)' | tr '[:upper:]' '[:lower:]')
ifeq ($(filter 1 true yes on,$(_PORTAL_ONLY)),)
  # APME plugins enabled — rewrite removed compose hostname if present in .env
  _APME_URL_RAW := $(if $(APME_BASE_URL),$(APME_BASE_URL),http://host.containers.internal:8080)
  ifneq ($(findstring apme-gateway,$(_APME_URL_RAW)),)
    override APME_BASE_URL := http://host.containers.internal:8080
  else
    override APME_BASE_URL := $(_APME_URL_RAW)
  endif
else
  override APME_BASE_URL :=
  # Normalize so recipe checks can use PORTAL_ONLY=1
  override PORTAL_ONLY := 1
endif

COMPOSE_PROFILES := $(shell echo '$(_PROFILES)' | tr ' ' ',')

export COMPOSE_PROFILES APME_BASE_URL PLUGIN_REPO APME_REPO SKIP_BUILD FORCE_EXPORT AAP_MOCK PORTAL_ONLY

# ── Compose file sets ────────────────────────────────────────────────
COMPOSE_F     := -f compose.yaml -f compose.portal.yaml
COMPOSE_F_DEV := $(COMPOSE_F) -f compose.portal.dev.yaml
ifneq ($(PORTAL_ONLY),1)
  COMPOSE_F_DEV += -f compose.apme.dev.yaml
endif

# ── Plugin lists (overridable: make reload PLUGINS="backstage-apme") ─
# Portal-only plugins (always included)
_PORTAL_PLUGINS := auth-backend-module-rhaap-provider \
                   catalog-backend-module-rhaap \
                   self-service \
                   scaffolder-backend-module-backstage-rhaap

# APME plugins (included only when APME is active)
_APME_PLUGINS := backstage-apme catalog-backend-module-apme

ifeq ($(PORTAL_ONLY),1)
  PLUGINS ?= $(_PORTAL_PLUGINS)
  FE_PLUGINS ?= self-service
else
  PLUGINS ?= $(_PORTAL_PLUGINS) $(_APME_PLUGINS)
  FE_PLUGINS ?= backstage-apme self-service
endif

# =====================================================================
#  User-facing targets
# =====================================================================
.PHONY: help dev start stop restart reload reload-fe dev-prompt export-plugins \
        build-plugins clean logs status check-plugin-parity apme apme-down

help: ## Show available targets
	@printf '\n\033[1mAutomation Portal Local\033[0m\n'
	@printf 'Usage: make <target> [VAR=value …]\n\n'
	@printf '\033[1mWhich dev loop?\033[0m\n\n'
	@printf '  \033[36mmake dev\033[0m         You are editing \033[1mplugin source\033[0m (TypeScript/React) in\n'
	@printf '                   ansible-backstage-plugins. Bind-mounts dist-dynamic into\n'
	@printf '                   RHDH — iterate with \033[36mmake reload\033[0m (backend changes) or\n'
	@printf '                   \033[36mmake reload-fe\033[0m (frontend-only, browser refresh).\n\n'
	@printf '  \033[36mmake start\033[0m       Production-shaped tarball mode: \033[1mbuilds\033[0m plugins from\n'
	@printf '                   PLUGIN_REPO, packs .tgz, then starts compose (same install path\n'
	@printf '                   as OpenShift). Use SKIP_BUILD=1 only for pre-downloaded CI tarballs.\n\n'
	@printf '  Both modes start the Almost-like-AAP mock by default and ensure APME is\n'
	@printf '  up via \033[36mmake apme\033[0m (\033[1mtox -e up\033[0m in APME_REPO). Set PORTAL_ONLY=1 for no APME.\n\n'
	@printf '\033[1mTargets\033[0m\n\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@printf '\n\033[1mOverrides\033[0m\n\n'
	@printf '  PLUGIN_REPO=<path>      Path to ansible-backstage-plugins clone\n'
	@printf '  APME_REPO=<path>        Path to apme clone (for make apme)\n'
	@printf '  PLUGINS="name …"        Limit export/reload/build to specific plugins\n'
	@printf '  FE_PLUGINS="name …"     Limit reload-fe to specific frontend plugins\n'
	@printf '  SKIP_BUILD=1            make start: skip rebuild, use existing .tgz\n'
	@printf '  FORCE_EXPORT=1          Rebuild all plugins (skip incremental export)\n'
	@printf '  DEV_PROMPT=0            Skip interactive R/F/S menu after make dev\n'
	@printf '  PORTAL_ONLY=1           No APME plugins; skip make apme (IAG / portal-only)\n\n'

apme: ## Start APME (cd APME_REPO && tox -e up)
	@[ -d "$(APME_REPO)" ] || { \
	  echo "ERROR: APME_REPO not found: $(APME_REPO)"; \
	  echo "Clone apme and set APME_REPO in .env (default: \$$HOME/github/apme)."; \
	  exit 1; }
	@command -v tox >/dev/null || { \
	  echo "ERROR: tox is required to start APME."; \
	  echo "  uv tool install tox --with tox-uv"; \
	  exit 1; }
	@echo "Starting APME via tox -e up in $(APME_REPO)…"
	@cd "$(APME_REPO)" && tox -e up

apme-down: ## Stop APME (cd APME_REPO && tox -e down)
	@[ -d "$(APME_REPO)" ] || { \
	  echo "ERROR: APME_REPO not found: $(APME_REPO)"; exit 1; }
	@command -v tox >/dev/null || { \
	  echo "ERROR: tox is required to stop APME."; exit 1; }
	@echo "Stopping APME via tox -e down in $(APME_REPO)…"
	@cd "$(APME_REPO)" && tox -e down

dev: check-plugin-parity _check-env _prereqs _stop-if-running _remove-legacy-apme _ensure-apme _submodule _overlays _overlays-dev _env-files _sync-template _export-plugins _seed-extensions _prep-dev-root _load-images ## Start DEV mode (mount dist-dynamic into RHDH)
	@echo "Starting services (DEV mounts)…"
	@cd $(RHDH_DIR) && podman compose $(COMPOSE_F_DEV) up -d
	@$(MAKE) --no-print-directory _banner-dev
	@DEV_PROMPT="$(DEV_PROMPT)" "$(ROOT_DIR)/scripts/dev-prompt.sh"

dev-prompt: ## Re-enter the interactive DEV menu (R/F/S) without restarting compose
	@DEV_PROMPT=1 "$(ROOT_DIR)/scripts/dev-prompt.sh"

start: check-plugin-parity _check-env _prereqs _stop-if-running _remove-legacy-apme _ensure-apme _submodule _maybe-build-tarballs _overlays _overlays-tarball _env-files _sync-template _tarballs _seed-extensions _prep-install-root _load-images ## Build tarballs from PLUGIN_REPO + start (production-shaped)
	@echo "Starting services…"
	@cd $(RHDH_DIR) && podman compose $(COMPOSE_F) up -d
	@$(MAKE) --no-print-directory _banner

check-plugin-parity: ## Fail if DEV vs tarball dynamic-plugins host contracts drift
	@python3 "$(ROOT_DIR)/scripts/check-plugin-config-parity.py"

stop: ## Stop Portal compose services (APME keeps running — use make apme-down)
	@if [ ! -f "$(RHDH_DIR)/compose.portal.yaml" ]; then \
	  echo "Portal does not appear to be running."; exit 0; \
	fi
	@cd $(RHDH_DIR) && \
	  if [ -f .env ]; then set -a; . ./.env; set +a; fi; \
	  if [ -f compose.portal.dev.yaml ]; then \
	    PLUGIN_REPO="$${PLUGIN_REPO:-}" podman compose $(COMPOSE_F_DEV) down; \
	  else \
	    podman compose $(COMPOSE_F) down; \
	  fi
	@echo "Portal services stopped. APME (if running): make apme-down"

restart: stop dev ## Restart DEV mode (stop + dev)

reload: _prereqs _export-plugins _clear-installer-lock ## Re-export changed plugins, reinstall, restart rhdh
	@echo "Re-running install-dynamic-plugins…"
	@cd $(RHDH_DIR) && PLUGIN_REPO="$(PLUGIN_REPO)" \
	  podman compose $(COMPOSE_F_DEV) run --rm --no-deps install-dynamic-plugins
	@echo "Restarting rhdh…"
	@cd $(RHDH_DIR) && PLUGIN_REPO="$(PLUGIN_REPO)" \
	  podman compose $(COMPOSE_F_DEV) restart rhdh
	@echo ""
	@echo "Reloaded. Hard-refresh http://localhost:7007"
	@echo "  UI-only next time: make reload-fe"

reload-fe: ## FE-only export into dynamic-plugins-root (browser refresh; incremental)
	@command -v yarn >/dev/null || { echo "ERROR: yarn required for FE export"; exit 1; }
	@[ -d "$(PLUGIN_REPO)" ] || { \
	  echo "ERROR: PLUGIN_REPO not found: $(PLUGIN_REPO)"; exit 1; }
	@PLUGIN_REPO="$(PLUGIN_REPO)" \
	  PLUGINS="$(FE_PLUGINS)" \
	  FORCE_EXPORT="$(FORCE_EXPORT)" \
	  EXPORT_DEV=1 \
	  DYNAMIC_PLUGINS_ROOT="$(RHDH_DIR)/dynamic-plugins-root" \
	  "$(ROOT_DIR)/scripts/export-portal-plugins.sh"
	@echo ""
	@echo "Done. Hard-refresh http://localhost:7007 (no container restart)."

export-plugins: _export-plugins ## Export dist-dynamic for all portal plugins

build-plugins: _build-tarballs ## Build plugin tarballs from PLUGIN_REPO (export + pack)

clean: ## Stop + remove volumes + clean copied overlays
	@if [ -f "$(RHDH_DIR)/compose.portal.yaml" ]; then \
	  echo "Stopping services and removing volumes…"; \
	  cd $(RHDH_DIR) && \
	  if [ -f .env ]; then set -a; . ./.env; set +a; fi; \
	  podman compose -f compose.yaml -f compose.portal.yaml down -v 2>/dev/null || true; \
	fi
	@echo "Removing overlay files from rhdh-local…"
	@rm -f  "$(RHDH_DIR)/compose.portal.yaml"
	@rm -f  "$(RHDH_DIR)/compose.portal.dev.yaml"
	@rm -f  "$(RHDH_DIR)/compose.apme.dev.yaml"
	@rm -f  "$(RHDH_DIR)/configs/app-config/app-config.portal.yaml"
	@rm -f  "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal.yaml"
	@rm -f  "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal.dev.yaml"
	@rm -rf "$(RHDH_DIR)/configs/catalog/apme-register-git-repository"
	@rm -f  "$(RHDH_DIR)/.env"
	@rm -f  "$(RHDH_DIR)/.portal-compose-mode"
	@rm -rf "$(RHDH_DIR)/local-plugins/portal"
	@rm -rf "$(RHDH_DIR)/local-plugins/portal-dev"
	@rm -rf "$(RHDH_DIR)/dynamic-plugins-root"
	@rm -f  "$(ROOT_DIR)/.env.platform"
	@echo "Cleanup complete. APME (if running): make apme-down"

logs: ## Follow compose logs (all services)
	@cd $(RHDH_DIR) && \
	  if [ -f .env ]; then set -a; . ./.env; set +a; fi; \
	  if [ -f compose.portal.dev.yaml ]; then \
	    PLUGIN_REPO="$${PLUGIN_REPO:-}" podman compose $(COMPOSE_F_DEV) logs -f; \
	  else \
	    podman compose $(COMPOSE_F) logs -f; \
	  fi

status: ## Show running containers
	@cd $(RHDH_DIR) && podman compose $(COMPOSE_F) ps 2>/dev/null || echo "Not running."


# =====================================================================
#  Internal targets (prefixed with _)
# =====================================================================
.PHONY: _check-env _prereqs _ensure-apme _remove-legacy-apme _stop-if-running _submodule \
        _overlays _overlays-dev _overlays-tarball _env-files _export-plugins _seed-extensions \
        _load-images _tarballs _sync-template _clear-installer-lock _prep-dev-root _prep-install-root \
        _build-tarballs _maybe-build-tarballs \
        _banner _banner-dev _banner-apme

_check-env:
	@[ -f "$(ROOT_DIR)/.env" ] || { \
	  echo "ERROR: .env not found."; \
	  echo "  cp .env.example .env"; \
	  exit 1; }
	@if grep -qE '^APME_EXTERNAL=|^APME_UI=|^APME_IMAGE_TAG=' "$(ROOT_DIR)/.env" 2>/dev/null; then \
	  echo "NOTE: APME_EXTERNAL / APME_UI / APME_IMAGE_TAG in .env are ignored."; \
	  echo "  APME runs via make apme (tox -e up). Remove those keys when convenient."; \
	fi
	@if grep -qE '^APME_BASE_URL=.*apme-gateway' "$(ROOT_DIR)/.env" 2>/dev/null; then \
	  echo "WARNING: APME_BASE_URL still points at compose hostname apme-gateway." >&2; \
	  echo "  Unset it (default: http://host.containers.internal:8080) or set a host Gateway URL." >&2; \
	fi
	@if [ -f "$(ROOT_DIR)/.env-abbenay" ]; then \
	  echo "NOTE: .env-abbenay is unused. Put Abbenay keys in APME_REPO/containers/abbenay/.env"; \
	fi

_prereqs:
	@command -v podman >/dev/null || { echo "ERROR: podman is required."; exit 1; }
	@command -v git    >/dev/null || { echo "ERROR: git is required."; exit 1; }

# Remove pre-unbundle compose APME containers (exact names). Does not touch apme-pod-*.
_remove-legacy-apme:
	@removed=0; \
	for c in apme-gateway apme-primary apme-abbenay apme-native apme-opa apme-ansible \
	  apme-gitleaks apme-collection-health apme-dep-audit apme-galaxy-proxy apme-ui; do \
	  if podman container exists "$$c" 2>/dev/null; then \
	    echo "Removing legacy compose APME container: $$c"; \
	    podman rm -f "$$c" >/dev/null 2>&1 || true; \
	    removed=1; \
	  fi; \
	done; \
	if [ "$$removed" = "1" ]; then \
	  echo "Legacy compose APME containers removed. Gateway now comes from: make apme"; \
	fi

# When APME plugins are enabled, ensure Gateway is reachable; otherwise run make apme
# for the default host URL only. Custom APME_BASE_URL → warn, do not tox-start.
_ensure-apme:
	@if [ "$(PORTAL_ONLY)" = "1" ]; then \
	  echo "PORTAL_ONLY=1 — skipping APME"; \
	else \
	  command -v curl >/dev/null || { \
	    echo "ERROR: curl is required to probe the APME Gateway (or set PORTAL_ONLY=1)."; \
	    exit 1; }; \
	  URL="$(APME_BASE_URL)"; \
	  DEFAULT_URL="http://host.containers.internal:8080"; \
	  case "$$URL" in \
	    *apme-gateway*) \
	      echo "WARNING: APME_BASE_URL uses removed compose hostname apme-gateway — using $$DEFAULT_URL" >&2; \
	      URL="$$DEFAULT_URL"; \
	      ;; \
	  esac; \
	  PROBE=$$(printf '%s' "$$URL" | sed 's/host\.containers\.internal/127.0.0.1/g'); \
	  if curl -sf --connect-timeout 2 --max-time 3 "$${PROBE%/}/docs" >/dev/null 2>&1; then \
	    echo "APME Gateway already up at $${PROBE}"; \
	  elif [ "$$URL" = "$$DEFAULT_URL" ] || [ "$$URL" = "http://127.0.0.1:8080" ] || [ "$$URL" = "http://localhost:8080" ]; then \
	    echo "APME Gateway not reachable at $${PROBE} — starting via make apme…"; \
	    $(MAKE) --no-print-directory apme; \
	  else \
	    echo "WARNING: APME Gateway at $${PROBE} did not respond." >&2; \
	    echo "  Start it yourself (make apme, or your remote Gateway), or unset APME_BASE_URL." >&2; \
	  fi; \
	fi

_stop-if-running:
	@if [ -f "$(RHDH_DIR)/compose.portal.yaml" ]; then \
	  cd $(RHDH_DIR) && \
	  if [ -f .env ]; then set -a; . ./.env; set +a; fi; \
	  RUNNING=$$(podman compose $(COMPOSE_F) ps -q 2>/dev/null | head -1); \
	  if [ -n "$$RUNNING" ]; then \
	    echo "Stopping existing stack before switching modes…"; \
	    if [ -f compose.portal.dev.yaml ]; then \
	      PLUGIN_REPO="$${PLUGIN_REPO:-}" podman compose $(COMPOSE_F_DEV) down; \
	    else \
	      podman compose $(COMPOSE_F) down; \
	    fi; \
	    $(MAKE) --no-print-directory _clear-installer-lock; \
	  fi; \
	fi

_submodule:
	@if [ ! -f "$(RHDH_DIR)/compose.yaml" ]; then \
	  echo "Initializing rhdh-local submodule…"; \
	  git -C "$(ROOT_DIR)" submodule update --init --recursive; \
	fi

_overlays: _submodule
	@mkdir -p \
	  "$(RHDH_DIR)/configs/app-config" \
	  "$(RHDH_DIR)/configs/dynamic-plugins" \
	  "$(RHDH_DIR)/configs/catalog" \
	  "$(RHDH_DIR)/local-plugins/portal" \
	  "$(RHDH_DIR)/local-plugins/portal-dev"
	@cp "$(OVERLAY)/app-config.portal.yaml" \
	    "$(RHDH_DIR)/configs/app-config/app-config.portal.yaml"
	@cp "$(OVERLAY)/compose.portal.yaml" \
	    "$(RHDH_DIR)/compose.portal.yaml"
	@cp "$(OVERLAY)/prepare-and-install-dynamic-plugins.sh" \
	    "$(RHDH_DIR)/prepare-and-install-dynamic-plugins.sh"
	@chmod +x "$(RHDH_DIR)/prepare-and-install-dynamic-plugins.sh"

_overlays-dev: _overlays
	@cp "$(OVERLAY)/compose.portal.dev.yaml" \
	    "$(RHDH_DIR)/compose.portal.dev.yaml"
	@if [ "$(PORTAL_ONLY)" != "1" ] && [ -f "$(OVERLAY)/compose.apme.dev.yaml" ]; then \
	  cp "$(OVERLAY)/compose.apme.dev.yaml" "$(RHDH_DIR)/compose.apme.dev.yaml"; \
	else \
	  rm -f "$(RHDH_DIR)/compose.apme.dev.yaml"; \
	fi
	@if [ "$(PORTAL_ONLY)" = "1" ]; then \
	  cp "$(OVERLAY)/dynamic-plugins.portal.dev.yaml" \
	     "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal.dev.yaml"; \
	else \
	  cp "$(OVERLAY)/dynamic-plugins.portal-apme.dev.yaml" \
	     "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal.dev.yaml"; \
	fi

_overlays-tarball: _overlays
	@rm -f "$(RHDH_DIR)/compose.portal.dev.yaml"
	@rm -f "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal.dev.yaml"
	@if [ "$(PORTAL_ONLY)" = "1" ]; then \
	  cp "$(OVERLAY)/dynamic-plugins.portal.yaml" \
	     "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal.yaml"; \
	else \
	  cp "$(OVERLAY)/dynamic-plugins.portal-apme.yaml" \
	     "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal.yaml"; \
	fi

_sync-template:
	@if [ "$(PORTAL_ONLY)" = "1" ]; then \
	  echo "SKIP: APME register template (PORTAL_ONLY=1)"; exit 0; \
	fi
	@REPO="$(PLUGIN_REPO)"; \
	SRC="$$REPO/plugins/backstage-apme/templates/apme-register-git-repository"; \
	DEST="$(RHDH_DIR)/configs/catalog/apme-register-git-repository"; \
	if [ ! -d "$$SRC" ]; then \
	  echo "SKIP: APME register template not found (APME not in PLUGIN_REPO)"; \
	  exit 0; \
	fi; \
	rm -f  "$(RHDH_DIR)/configs/catalog/apme-register-git-repository.yaml"; \
	rm -rf "$$DEST"; \
	cp -a  "$$SRC" "$$DEST"; \
	echo "Synced register template from $$SRC"

_env-files:
	@ARCH=$$(uname -m); \
	if [ "$$ARCH" = "arm64" ] || [ "$$ARCH" = "aarch64" ]; then \
	  printf 'OPENSSL_CONF=/dev/null\n' > "$(ROOT_DIR)/.env.platform"; \
	  echo "Detected ARM host — set OPENSSL_CONF=/dev/null for portal containers"; \
	else \
	  : > "$(ROOT_DIR)/.env.platform"; \
	fi; \
	cat "$(ROOT_DIR)/.env" "$(ROOT_DIR)/.env.platform" > "$(RHDH_DIR)/.env"; \
	for pair in \
	  "COMPOSE_PROFILES=$(COMPOSE_PROFILES)" \
	  "APME_BASE_URL=$(APME_BASE_URL)" \
	  "PLUGIN_REPO=$(PLUGIN_REPO)"; do \
	  key="$${pair%%=*}"; \
	  grep -v "^$$key=" "$(RHDH_DIR)/.env" > "$(RHDH_DIR)/.env.tmp" 2>/dev/null || true; \
	  mv "$(RHDH_DIR)/.env.tmp" "$(RHDH_DIR)/.env"; \
	  echo "$$pair" >> "$(RHDH_DIR)/.env"; \
	done

_build-tarballs: _export-plugins
	@command -v npm >/dev/null || { echo "ERROR: npm required to pack plugin tarballs"; exit 1; }
	@echo "=== Pack portal plugin tarballs ==="
	@$(ROOT_DIR)/scripts/pack-portal-plugins.sh \
	  "$(PLUGIN_REPO)" \
	  "$(ROOT_DIR)/local-plugins/portal" \
	  "$(PLUGINS)"

_maybe-build-tarballs:
	@if [ "$(SKIP_BUILD)" = "1" ]; then \
	  echo "SKIP_BUILD=1 — using existing tarballs in local-plugins/portal/"; \
	  if ! compgen -G "$(ROOT_DIR)/local-plugins/portal/"*.tgz >/dev/null 2>&1; then \
	    echo "ERROR: No plugin tarballs found in local-plugins/portal/"; \
	    echo "Drop SKIP_BUILD or run: make build-plugins"; \
	    exit 1; \
	  fi; \
	else \
	  $(MAKE) --no-print-directory _build-tarballs; \
	fi

_tarballs:
	@rm -f $(RHDH_DIR)/local-plugins/portal/*.tgz 2>/dev/null || true
	@if compgen -G "$(ROOT_DIR)/local-plugins/portal/"*.tgz >/dev/null 2>&1; then \
	  cp "$(ROOT_DIR)/local-plugins/portal/"*.tgz \
	     "$(RHDH_DIR)/local-plugins/portal/"; \
	  echo "Copied plugin tarballs:"; \
	  ls -1 "$(RHDH_DIR)/local-plugins/portal/"*.tgz; \
	else \
	  echo "ERROR: No plugin tarballs found in local-plugins/portal/"; \
	  echo ""; \
	  echo "For dev (bind-mount):     make dev"; \
	  echo "For tarballs:             make start   (builds from PLUGIN_REPO)"; \
	  echo "CI artifacts only:        make start SKIP_BUILD=1"; \
	  exit 1; \
	fi

# Remove stale install-dynamic-plugins.lock left when a prior installer was killed
# (Ctrl+C during make dev). Upstream install-dynamic-plugins.py waits forever.
_clear-installer-lock:
	@if [ -f "$(RHDH_DIR)/dynamic-plugins-root/install-dynamic-plugins.lock" ]; then \
	  echo "Removing stale install-dynamic-plugins.lock…"; \
	  rm -f "$(RHDH_DIR)/dynamic-plugins-root/install-dynamic-plugins.lock"; \
	fi
	@VOL=$$(podman volume ls -q 2>/dev/null | grep -E '(^|_)dynamic-plugins-root$$' | head -1 || true); \
	if [ -n "$$VOL" ]; then \
	  podman run --rm -v "$$VOL:/dynamic-plugins-root" alpine \
	    sh -c 'rm -f /dynamic-plugins-root/install-dynamic-plugins.lock' 2>/dev/null || true; \
	fi

# Wipe previously installed portal plugins so install-dynamic-plugins cannot
# treat same name@version as already_installed.
#
# Important: make start uses the named compose volume
#   rhdh-local_dynamic-plugins-root
# make dev bind-mounts the host dir
#   rhdh-local/dynamic-plugins-root
# Clearing only the host dir does nothing for make start — the installer keeps
# skipping rebuilt .tgz files and you lose Overview Quality / README fixes.
_prep-install-root: _clear-installer-lock
	@mkdir -p "$(RHDH_DIR)/dynamic-plugins-root"
	@echo "Clearing host dynamic-plugins-root portal plugin installs…"
	@find "$(RHDH_DIR)/dynamic-plugins-root" -maxdepth 1 -mindepth 1 \
	  -name 'ansible-*' -exec rm -rf {} + 2>/dev/null || true
	@touch "$(RHDH_DIR)/dynamic-plugins-root/app-config.dynamic-plugins.yaml"
	@VOL=$$(podman volume ls -q 2>/dev/null | grep -E '(^|_)dynamic-plugins-root$$' | head -1 || true); \
	if [ -n "$$VOL" ]; then \
	  echo "Clearing named volume $$VOL portal plugin installs…"; \
	  podman run --rm -v "$$VOL:/dynamic-plugins-root" alpine \
	    sh -c 'find /dynamic-plugins-root -mindepth 1 -maxdepth 1 -name "ansible-*" -exec rm -rf {} +' \
	    || true; \
	fi

_prep-dev-root: _prep-install-root

_seed-extensions:
	@mkdir -p "$(RHDH_DIR)/dynamic-plugins-root" "$(RHDH_DIR)/extensions-catalog"
	@chmod -R a+rwX "$(RHDH_DIR)/extensions-catalog" 2>/dev/null || true
	@printf '%s\n' \
	  '# Prevent Extensions installer from GC-deleting portal plugins.' \
	  'includes: []' \
	  'plugins: []' \
	  > "$(RHDH_DIR)/dynamic-plugins-root/dynamic-plugins.extensions.yaml"

_export-plugins:
	@command -v yarn >/dev/null || { echo "ERROR: yarn required for plugin export"; exit 1; }
	@[ -d "$(PLUGIN_REPO)" ] || { \
	  echo "ERROR: PLUGIN_REPO not found: $(PLUGIN_REPO)"; \
	  echo "Set PLUGIN_REPO in .env or on the command line."; \
	  exit 1; }
	@PLUGIN_REPO="$(PLUGIN_REPO)" PLUGINS="$(PLUGINS)" FORCE_EXPORT="$(FORCE_EXPORT)" \
	  "$(ROOT_DIR)/scripts/export-portal-plugins.sh"

_load-images:
	@if [ -d "$(ROOT_DIR)/images" ] && compgen -G "$(ROOT_DIR)/images/*.tar.gz" >/dev/null 2>&1; then \
	  echo "Loading APME container images from archives…"; \
	  "$(ROOT_DIR)/scripts/load-images.sh"; \
	fi

_banner:
	@echo ""
	@echo "=== Portal is starting (tarball mode) ==="
	@echo "  Portal UI:     http://localhost:7007"
	@$(MAKE) --no-print-directory _banner-apme
	@if [ "$(SKIP_BUILD)" = "1" ]; then \
	  echo "  Plugins:       existing .tgz (SKIP_BUILD=1)"; \
	else \
	  echo "  Plugins:       rebuilt from $(PLUGIN_REPO)"; \
	fi
	@echo ""
	@echo "  View logs:     make logs"
	@echo "  Stop:          make stop"
	@echo ""

_banner-dev:
	@echo ""
	@echo "=== Portal DEV is starting ==="
	@echo "  Portal UI:       http://localhost:7007"
	@$(MAKE) --no-print-directory _banner-apme
	@echo "  Almost like AAP: http://localhost:8099"
	@echo "  Login:           user / password  (Almost like AAP mock)"
	@echo "  PLUGIN_REPO:     $(PLUGIN_REPO)"
	@echo ""
	@echo "  Interactive menu (after this banner):"
	@echo "    [R] reload     [F] frontend     [S] stop     [Q] quit menu"
	@echo "  Or: make reload / make reload-fe / make stop / make dev-prompt"
	@echo ""

_banner-apme:
	@if [ "$(PORTAL_ONLY)" = "1" ]; then \
	  echo "  APME:            disabled (PORTAL_ONLY=1)"; \
	else \
	  echo "  APME Gateway:    http://localhost:8080  (make apme → tox -e up)"; \
	  echo "  APME UI:         http://localhost:8081  (from APME pod)"; \
	  echo "  Abbenay UI:      http://localhost:8787  (from APME pod)"; \
	  echo "  RHDH→APME URL:   $(APME_BASE_URL)"; \
	fi
