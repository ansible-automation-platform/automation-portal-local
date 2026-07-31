#!/usr/bin/env python3
"""Fail if DEV and tarball dynamic-plugins host contracts drift.

RHDH registers frontend apiFactories / routes / mountPoints from pluginConfig,
not from the plugin package alone. Updating only
overlay/dynamic-plugins.portal-apme.dev.yaml leaves ``make start`` broken.

Usage:
  python3 scripts/check-plugin-config-parity.py
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    print("PyYAML is required: pip install pyyaml", file=sys.stderr)
    raise SystemExit(2) from exc

ROOT = Path(__file__).resolve().parents[1]
DEV_YAML = ROOT / "overlay" / "dynamic-plugins.portal-apme.dev.yaml"
TARBALL_YAML = ROOT / "overlay" / "dynamic-plugins.portal-apme.yaml"

# Plugin IDs whose host contract must match between DEV and tarball modes.
FRONTEND_PARITY_IDS = (
    "ansible.plugin-backstage-apme",
    "ansible.plugin-backstage-self-service",
)
BACKEND_PARITY_IDS = ("ansible.backstage-plugin-catalog-backend-module-apme",)

# Keys whose importName / path sets must be present in tarball whenever DEV has them.
FRONTEND_LIST_KEYS = (
    "apiFactories",
    "scaffolderFieldExtensions",
    "dynamicRoutes",
    "mountPoints",
    "entityTabs",
    "analyticsApiExtensions",
    "providerSettings",
)


def _load(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise SystemExit(f"Missing required file: {path}")
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"Expected mapping at root of {path}")
    return data


def _collect_plugin_configs(
    doc: dict[str, Any],
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    """Return (frontend_id -> config, backend_id -> config)."""
    frontend: dict[str, dict[str, Any]] = {}
    backend: dict[str, Any] = {}
    for entry in doc.get("plugins") or []:
        if not isinstance(entry, dict) or entry.get("disabled"):
            continue
        pc = entry.get("pluginConfig") or {}
        if not isinstance(pc, dict):
            continue
        dyn = pc.get("dynamicPlugins") or {}
        if not isinstance(dyn, dict):
            continue
        for name, cfg in (dyn.get("frontend") or {}).items():
            if isinstance(cfg, dict):
                frontend[name] = cfg
        for name, cfg in (dyn.get("backend") or {}).items():
            backend[name] = cfg
    return frontend, backend


def _names(items: Any, name_key: str = "importName") -> set[str]:
    out: set[str] = set()
    if not isinstance(items, list):
        return out
    for item in items:
        if isinstance(item, dict):
            val = item.get(name_key)
            if isinstance(val, str) and val:
                out.add(val)
            # entityTabs use path as identity when importName absent
            path = item.get("path")
            if name_key == "path" and isinstance(path, str) and path:
                out.add(path)
    return out


def _compare_frontend(
    plugin_id: str,
    dev_cfg: dict[str, Any],
    tarball_cfg: dict[str, Any] | None,
) -> list[str]:
    errors: list[str] = []
    if tarball_cfg is None:
        return [
            f"{plugin_id}: present in DEV pluginConfig but missing from tarball YAML"
        ]
    for key in FRONTEND_LIST_KEYS:
        if key not in dev_cfg:
            continue
        name_key = "path" if key == "entityTabs" else "importName"
        # entityTabs: require both path and importName-less path set; also title tabs
        if key == "entityTabs":
            dev_paths = _names(dev_cfg.get(key), "path")
            tar_paths = _names(tarball_cfg.get(key), "path")
            missing = sorted(dev_paths - tar_paths)
            if missing:
                errors.append(
                    f"{plugin_id}.{key}: tarball missing path(s) {missing} (DEV has them)"
                )
            continue
        if key == "providerSettings":
            # Compare provider ids
            def providers(cfg: dict[str, Any]) -> set[str]:
                out: set[str] = set()
                for item in cfg.get(key) or []:
                    if isinstance(item, dict) and isinstance(item.get("provider"), str):
                        out.add(item["provider"])
                return out

            missing = sorted(providers(dev_cfg) - providers(tarball_cfg))
            if missing:
                errors.append(
                    f"{plugin_id}.{key}: tarball missing provider(s) {missing}"
                )
            continue

        dev_names = _names(dev_cfg.get(key), name_key)
        tar_names = _names(tarball_cfg.get(key), name_key)
        missing = sorted(dev_names - tar_names)
        if missing:
            errors.append(
                f"{plugin_id}.{key}: tarball missing importName(s) {missing} (DEV has them)"
            )
    return errors


def main() -> int:
    dev = _load(DEV_YAML)
    tarball = _load(TARBALL_YAML)
    dev_fe, dev_be = _collect_plugin_configs(dev)
    tar_fe, tar_be = _collect_plugin_configs(tarball)

    errors: list[str] = []

    for plugin_id in FRONTEND_PARITY_IDS:
        if plugin_id not in dev_fe:
            errors.append(
                f"{plugin_id}: expected in DEV YAML frontend pluginConfig, not found"
            )
            continue
        errors.extend(_compare_frontend(plugin_id, dev_fe[plugin_id], tar_fe.get(plugin_id)))

    for plugin_id in BACKEND_PARITY_IDS:
        if plugin_id not in dev_be:
            errors.append(
                f"{plugin_id}: expected in DEV YAML backend pluginConfig, not found"
            )
            continue
        if plugin_id not in tar_be:
            errors.append(
                f"{plugin_id}: present in DEV backend pluginConfig but missing from tarball YAML"
            )

    # Hard requirement that caused Git Repos NotImplementedError
    apme = tar_fe.get("ansible.plugin-backstage-apme") or {}
    factories = _names(apme.get("apiFactories"))
    if "gitRepositoriesExtensionsApiFactory" not in factories:
        errors.append(
            "ansible.plugin-backstage-apme.apiFactories must include "
            "gitRepositoriesExtensionsApiFactory in tarball YAML "
            "(self-service Git Repos useApi requires it)"
        )
    if "apmeApiFactory" not in factories:
        errors.append(
            "ansible.plugin-backstage-apme.apiFactories must include apmeApiFactory "
            "in tarball YAML"
        )

    if errors:
        print("Plugin host-config parity check FAILED:\n", file=sys.stderr)
        for err in errors:
            print(f"  ✗ {err}", file=sys.stderr)
        print(
            "\nUpdate overlay/dynamic-plugins.portal-apme.yaml to match "
            "overlay/dynamic-plugins.portal-apme.dev.yaml for the host contract "
            "(see AGENTS.md).",
            file=sys.stderr,
        )
        return 1

    print("Plugin host-config parity check OK")
    print(f"  DEV:     {DEV_YAML.relative_to(ROOT)}")
    print(f"  tarball: {TARBALL_YAML.relative_to(ROOT)}")
    for plugin_id in FRONTEND_PARITY_IDS:
        factories = sorted(_names((tar_fe.get(plugin_id) or {}).get("apiFactories")))
        print(f"  {plugin_id} apiFactories: {factories}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
