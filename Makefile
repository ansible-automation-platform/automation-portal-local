# Automation Portal Local — Makefile
#
# Primary interface for managing the local Portal + APME compose stack.
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
APME_EXTERNAL ?= 0
APME_UI       ?= 1
APME_IMAGE_TAG ?= latest
APME_BASE_URL ?=
# Set SKIP_BUILD=1 to use existing local-plugins/portal-apme/*.tgz (CI artifacts).
SKIP_BUILD    ?= 0
# Set FORCE_EXPORT=1 to rebuild every plugin (ignore incremental dist-dynamic stamps).
FORCE_EXPORT  ?= 0
# Set DEV_PROMPT=0 to skip the interactive R/F/S menu after make dev.
DEV_PROMPT    ?= 1

# ── APME compose-profile resolution ─────────────────────────────────
# Replaces the profile-manipulation bash functions from lib.sh.
ifeq ($(APME_EXTERNAL),1)
  COMPOSE_PROFILES :=
  override APME_BASE_URL := $(if $(APME_BASE_URL),$(APME_BASE_URL),http://host.containers.internal:8080)
else
  _UI := $(shell echo '$(APME_UI)' | tr '[:upper:]' '[:lower:]')
  ifneq ($(filter 0 false no off,$(_UI)),)
    COMPOSE_PROFILES := apme
  else
    COMPOSE_PROFILES := apme,apme-ui
  endif
  override APME_BASE_URL := $(if $(APME_BASE_URL),$(APME_BASE_URL),http://apme-gateway:8080)
endif

export COMPOSE_PROFILES APME_BASE_URL PLUGIN_REPO SKIP_BUILD FORCE_EXPORT

# ── Compose file sets ────────────────────────────────────────────────
COMPOSE_F     := -f compose.yaml -f compose.portal-apme.yaml
COMPOSE_F_DEV := $(COMPOSE_F) -f compose.portal-apme.dev.yaml

# ── Plugin lists (overridable: make reload PLUGINS="backstage-apme") ─
PLUGINS ?= auth-backend-module-rhaap-provider \
           catalog-backend-module-rhaap \
           self-service \
           scaffolder-backend-module-backstage-rhaap \
           backstage-apme \
           catalog-backend-module-apme

FE_PLUGINS ?= backstage-apme self-service

# =====================================================================
#  User-facing targets
# =====================================================================
.PHONY: help dev start stop restart reload reload-fe dev-prompt export-plugins \
        build-plugins clean logs status check-plugin-parity

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
	@printf '  Both modes start APME + Almost-like-AAP mock. Set APME_EXTERNAL=1 in .env\n'
	@printf '  to skip the compose APME stack and point at a Gateway you run separately.\n\n'
	@printf '\033[1mTargets\033[0m\n\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@printf '\n\033[1mOverrides\033[0m\n\n'
	@printf '  PLUGIN_REPO=<path>      Path to ansible-backstage-plugins clone\n'
	@printf '  PLUGINS="name …"        Limit export/reload/build to specific plugins\n'
	@printf '  FE_PLUGINS="name …"     Limit reload-fe to specific frontend plugins\n'
	@printf '  SKIP_BUILD=1            make start: skip rebuild, use existing .tgz\n'
	@printf '  FORCE_EXPORT=1          Rebuild all plugins (skip incremental export)\n'
	@printf '  DEV_PROMPT=0            Skip interactive R/F/S menu after make dev\n'
	@printf '  APME_EXTERNAL=1         Use an already-running APME Gateway\n\n'

dev: check-plugin-parity _check-env _prereqs _stop-if-running _submodule _overlays _overlays-dev _env-files _sync-template _export-plugins _seed-extensions _prep-dev-root _load-images ## Start DEV mode (mount dist-dynamic into RHDH)
	@echo "Starting services (DEV mounts)…"
	@cd $(RHDH_DIR) && podman compose $(COMPOSE_F_DEV) up -d
	@$(MAKE) --no-print-directory _banner-dev
	@DEV_PROMPT="$(DEV_PROMPT)" "$(ROOT_DIR)/scripts/dev-prompt.sh"

dev-prompt: ## Re-enter the interactive DEV menu (R/F/S) without restarting compose
	@DEV_PROMPT=1 "$(ROOT_DIR)/scripts/dev-prompt.sh"

start: check-plugin-parity _check-env _prereqs _stop-if-running _submodule _maybe-build-tarballs _overlays _overlays-tarball _env-files _sync-template _tarballs _seed-extensions _prep-install-root _load-images ## Build tarballs from PLUGIN_REPO + start (production-shaped)
	@echo "Starting services…"
	@cd $(RHDH_DIR) && podman compose $(COMPOSE_F) up -d
	@$(MAKE) --no-print-directory _banner

check-plugin-parity: ## Fail if DEV vs tarball dynamic-plugins host contracts drift
	@python3 "$(ROOT_DIR)/scripts/check-plugin-config-parity.py"

stop: ## Stop all services (auto-detects mode)
	@if [ ! -f "$(RHDH_DIR)/compose.portal-apme.yaml" ]; then \
	  echo "Portal does not appear to be running."; exit 0; \
	fi
	@cd $(RHDH_DIR) && \
	  if [ -f .env ]; then set -a; . ./.env; set +a; fi; \
	  if [ -f compose.portal-apme.dev.yaml ]; then \
	    PLUGIN_REPO="$${PLUGIN_REPO:-}" podman compose $(COMPOSE_F_DEV) down; \
	  else \
	    podman compose $(COMPOSE_F) down; \
	  fi
	@echo "All services stopped."

restart: stop dev ## Restart DEV mode (stop + dev)

reload: _prereqs _export-plugins ## Re-export changed plugins, reinstall, restart rhdh
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
	@if [ -f "$(RHDH_DIR)/compose.portal-apme.yaml" ]; then \
	  echo "Stopping services and removing volumes…"; \
	  cd $(RHDH_DIR) && \
	  if [ -f .env ]; then set -a; . ./.env; set +a; fi; \
	  podman compose -f compose.yaml -f compose.portal-apme.yaml down -v 2>/dev/null || true; \
	fi
	@echo "Removing overlay files from rhdh-local…"
	@rm -f  "$(RHDH_DIR)/compose.portal-apme.yaml"
	@rm -f  "$(RHDH_DIR)/compose.portal-apme.dev.yaml"
	@rm -f  "$(RHDH_DIR)/configs/app-config/app-config.portal-apme.yaml"
	@rm -f  "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal-apme.yaml"
	@rm -f  "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal-apme.dev.yaml"
	@rm -rf "$(RHDH_DIR)/configs/catalog/apme-register-git-repository"
	@rm -f  "$(RHDH_DIR)/.env"
	@rm -f  "$(RHDH_DIR)/.env-abbenay"
	@rm -rf "$(RHDH_DIR)/abbenay-config"
	@rm -f  "$(RHDH_DIR)/.portal-compose-mode"
	@rm -rf "$(RHDH_DIR)/local-plugins/portal-apme"
	@rm -rf "$(RHDH_DIR)/local-plugins/portal-apme-dev"
	@rm -rf "$(RHDH_DIR)/dynamic-plugins-root"
	@rm -f  "$(ROOT_DIR)/.env.platform"
	@echo "Cleanup complete."

clean-images: clean ## clean + remove APME container images
	@echo "Removing APME container images…"
	@for svc in gateway primary native opa ansible gitleaks collection-health dep-audit galaxy-proxy ui; do \
	  podman rmi "ghcr.io/ansible/apme-$$svc:$(APME_IMAGE_TAG)" 2>/dev/null || true; \
	done
	@podman rmi "postgres:16-alpine" 2>/dev/null || true
	@echo "APME images removed."

logs: ## Follow compose logs (all services)
	@cd $(RHDH_DIR) && \
	  if [ -f .env ]; then set -a; . ./.env; set +a; fi; \
	  if [ -f compose.portal-apme.dev.yaml ]; then \
	    PLUGIN_REPO="$${PLUGIN_REPO:-}" podman compose $(COMPOSE_F_DEV) logs -f; \
	  else \
	    podman compose $(COMPOSE_F) logs -f; \
	  fi

status: ## Show running containers
	@cd $(RHDH_DIR) && podman compose $(COMPOSE_F) ps 2>/dev/null || echo "Not running."


# =====================================================================
#  Internal targets (prefixed with _)
# =====================================================================
.PHONY: _check-env _prereqs _stop-if-running _submodule _overlays _overlays-dev \
        _overlays-tarball _env-files _export-plugins _seed-extensions \
        _load-images _tarballs _sync-template _prep-dev-root _prep-install-root \
        _build-tarballs _maybe-build-tarballs \
        _banner _banner-dev _banner-apme

_check-env:
	@[ -f "$(ROOT_DIR)/.env" ] || { \
	  echo "ERROR: .env not found."; \
	  echo "  cp .env.example .env"; \
	  exit 1; }

_prereqs:
	@command -v podman >/dev/null || { echo "ERROR: podman is required."; exit 1; }
	@command -v git    >/dev/null || { echo "ERROR: git is required."; exit 1; }

_stop-if-running:
	@if [ -f "$(RHDH_DIR)/compose.portal-apme.yaml" ]; then \
	  cd $(RHDH_DIR) && \
	  if [ -f .env ]; then set -a; . ./.env; set +a; fi; \
	  RUNNING=$$(podman compose $(COMPOSE_F) ps -q 2>/dev/null | head -1); \
	  if [ -n "$$RUNNING" ]; then \
	    echo "Stopping existing stack before switching modes…"; \
	    if [ -f compose.portal-apme.dev.yaml ]; then \
	      PLUGIN_REPO="$${PLUGIN_REPO:-}" podman compose $(COMPOSE_F_DEV) down; \
	    else \
	      podman compose $(COMPOSE_F) down; \
	    fi; \
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
	  "$(RHDH_DIR)/local-plugins/portal-apme" \
	  "$(RHDH_DIR)/local-plugins/portal-apme-dev" \
	  "$(RHDH_DIR)/abbenay-config"
	@cp "$(OVERLAY)/app-config.portal-apme.yaml" \
	    "$(RHDH_DIR)/configs/app-config/app-config.portal-apme.yaml"
	@cp "$(OVERLAY)/compose.portal-apme.yaml" \
	    "$(RHDH_DIR)/compose.portal-apme.yaml"
	@if [ ! -f "$(RHDH_DIR)/abbenay-config/config.yaml" ]; then \
	  cp "$(OVERLAY)/abbenay/config.yaml.example" \
	     "$(RHDH_DIR)/abbenay-config/config.yaml"; \
	  echo "Seeded rhdh-local/abbenay-config/config.yaml from overlay example"; \
	fi

_overlays-dev: _overlays
	@cp "$(OVERLAY)/compose.portal-apme.dev.yaml" \
	    "$(RHDH_DIR)/compose.portal-apme.dev.yaml"
	@cp "$(OVERLAY)/dynamic-plugins.portal-apme.dev.yaml" \
	    "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal-apme.dev.yaml"

_overlays-tarball: _overlays
	@rm -f "$(RHDH_DIR)/compose.portal-apme.dev.yaml"
	@rm -f "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal-apme.dev.yaml"
	@cp "$(OVERLAY)/dynamic-plugins.portal-apme.yaml" \
	    "$(RHDH_DIR)/configs/dynamic-plugins/dynamic-plugins.portal-apme.yaml"

_sync-template:
	@REPO="$(PLUGIN_REPO)"; \
	SRC="$$REPO/plugins/backstage-apme/templates/apme-register-git-repository"; \
	DEST="$(RHDH_DIR)/configs/catalog/apme-register-git-repository"; \
	if [ ! -d "$$SRC" ]; then \
	  echo "ERROR: APME register template not found at: $$SRC" >&2; \
	  echo "Set PLUGIN_REPO to ansible-backstage-plugins." >&2; \
	  exit 1; \
	fi; \
	rm -f  "$(RHDH_DIR)/configs/catalog/apme-register-git-repository.yaml"; \
	rm -rf "$$DEST"; \
	cp -a  "$$SRC" "$$DEST"; \
	echo "Synced register template from $$SRC"

_env-files:
	@ARCH=$$(uname -m); \
	if [ "$$ARCH" = "arm64" ] || [ "$$ARCH" = "aarch64" ]; then \
	  printf 'APME_PLATFORM=linux/amd64\nOPENSSL_CONF=/dev/null\n' > "$(ROOT_DIR)/.env.platform"; \
	  echo "Detected ARM host — APME containers will use amd64 emulation"; \
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
	@# Abbenay env_file (required by compose even when empty / APME_EXTERNAL=1)
	@if [ -f "$(ROOT_DIR)/.env-abbenay" ]; then \
	  cp "$(ROOT_DIR)/.env-abbenay" "$(RHDH_DIR)/.env-abbenay"; \
	elif [ -f "$(ROOT_DIR)/.env-abbenay.example" ]; then \
	  cp "$(ROOT_DIR)/.env-abbenay.example" "$(RHDH_DIR)/.env-abbenay"; \
	  echo "NOTE: Using .env-abbenay.example (no secrets). For AI keys: cp .env-abbenay.example .env-abbenay"; \
	else \
	  printf 'APME_ABBENAY_TOKEN=apme-dev-token\n' > "$(RHDH_DIR)/.env-abbenay"; \
	fi
	@if [ "$(APME_EXTERNAL)" = "1" ]; then \
	  URL="$(APME_BASE_URL)"; \
	  PROBE="$${URL//host.containers.internal/127.0.0.1}"; \
	  if ! curl -sf --connect-timeout 2 --max-time 3 "$${PROBE%/}/docs" >/dev/null 2>&1 \
	    && ! curl -sf --connect-timeout 2 --max-time 3 "$${PROBE%/}/" >/dev/null 2>&1; then \
	    echo "WARNING: APME_EXTERNAL=1 but Gateway at $${PROBE} did not respond." >&2; \
	    echo "  Start APME first (e.g. cd apme && tox -e up), or set APME_BASE_URL." >&2; \
	  fi; \
	fi

_build-tarballs: _export-plugins
	@command -v npm >/dev/null || { echo "ERROR: npm required to pack plugin tarballs"; exit 1; }
	@echo "=== Pack portal plugin tarballs ==="
	@$(ROOT_DIR)/scripts/pack-portal-plugins.sh \
	  "$(PLUGIN_REPO)" \
	  "$(ROOT_DIR)/local-plugins/portal-apme" \
	  "$(PLUGINS)"

_maybe-build-tarballs:
	@if [ "$(SKIP_BUILD)" = "1" ]; then \
	  echo "SKIP_BUILD=1 — using existing tarballs in local-plugins/portal-apme/"; \
	  if ! compgen -G "$(ROOT_DIR)/local-plugins/portal-apme/"*.tgz >/dev/null 2>&1; then \
	    echo "ERROR: No plugin tarballs found in local-plugins/portal-apme/"; \
	    echo "Drop SKIP_BUILD or run: make build-plugins"; \
	    exit 1; \
	  fi; \
	else \
	  $(MAKE) --no-print-directory _build-tarballs; \
	fi

_tarballs:
	@rm -f $(RHDH_DIR)/local-plugins/portal-apme/*.tgz 2>/dev/null || true
	@if compgen -G "$(ROOT_DIR)/local-plugins/portal-apme/"*.tgz >/dev/null 2>&1; then \
	  cp "$(ROOT_DIR)/local-plugins/portal-apme/"*.tgz \
	     "$(RHDH_DIR)/local-plugins/portal-apme/"; \
	  echo "Copied plugin tarballs:"; \
	  ls -1 "$(RHDH_DIR)/local-plugins/portal-apme/"*.tgz; \
	else \
	  echo "ERROR: No plugin tarballs found in local-plugins/portal-apme/"; \
	  echo ""; \
	  echo "For dev (bind-mount):     make dev"; \
	  echo "For tarballs:             make start   (builds from PLUGIN_REPO)"; \
	  echo "CI artifacts only:        make start SKIP_BUILD=1"; \
	  exit 1; \
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
_prep-install-root:
	@mkdir -p "$(RHDH_DIR)/dynamic-plugins-root"
	@echo "Clearing host dynamic-plugins-root ansible/backstage installs…"
	@find "$(RHDH_DIR)/dynamic-plugins-root" -maxdepth 1 -mindepth 1 \
	  \( -name 'ansible-*' -o -name 'backstage-*' \) -exec rm -rf {} + 2>/dev/null || true
	@touch "$(RHDH_DIR)/dynamic-plugins-root/app-config.dynamic-plugins.yaml"
	@VOL=$$(podman volume ls -q 2>/dev/null | grep -E '(^|_)dynamic-plugins-root$$' | head -1 || true); \
	if [ -n "$$VOL" ]; then \
	  echo "Clearing named volume $$VOL (used by make start / tarball mode)…"; \
	  podman run --rm -v "$$VOL:/dynamic-plugins-root:Z" alpine \
	    sh -c 'find /dynamic-plugins-root -mindepth 1 -maxdepth 1 \( -name "ansible-*" -o -name "backstage-*" \) -exec rm -rf {} +' \
	    || true; \
	fi

_prep-dev-root: _prep-install-root

_seed-extensions:
	@mkdir -p "$(RHDH_DIR)/dynamic-plugins-root"
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
	@if [ "$(APME_EXTERNAL)" = "1" ]; then \
	  echo "  APME:            external → $(APME_BASE_URL)"; \
	  echo "  APME UI:         use the external stack (e.g. http://localhost:8081)"; \
	else \
	  echo "  APME Gateway:    http://localhost:8080"; \
	  UI="$$(echo '$(APME_UI)' | tr '[:upper:]' '[:lower:]')"; \
	  case "$$UI" in 0|false|no|off) ;; *) \
	    echo "  APME UI:         http://localhost:$${APME_UI_PORT:-8081}" ;; \
	  esac; \
	fi
