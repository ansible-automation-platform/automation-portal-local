#!/usr/bin/env python3
"""Preserve Extensions click-install state and fill missing pluginConfig.

RHDH 1.10 click-install writes package refs into
dynamic-plugins.extensions.yaml but does not copy Package appConfigExamples
(apiFactories, entityTabs, mountPoints). Without those, APME loads as files
and Git Repos still has no guest factory.

This script:
  - creates the file if missing (empty plugins list — guests come from the UI)
  - never clears an existing plugins list
  - copies pluginConfig from overlay/catalog-index Package YAML when a guest
    package is present without config
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    print("PyYAML is required: pip install pyyaml", file=sys.stderr)
    raise SystemExit(2) from exc

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "overlay" / "catalog-index"
DEFAULT_DOC: dict[str, Any] = {
    "includes": [],
    "plugins": [],
}


def _layer_name(package_ref: str) -> str:
    ref = str(package_ref or "").strip()
    if "!" in ref:
        return ref.rsplit("!", 1)[-1]
    return Path(ref.rstrip("/")).name


def load_package_configs(catalog_index: Path) -> dict[str, dict[str, Any]]:
    """Map Package metadata.name → first appConfigExamples content."""
    configs: dict[str, dict[str, Any]] = {}
    packages_dir = catalog_index / "catalog-entities" / "extensions" / "packages"
    if not packages_dir.is_dir():
        return configs
    for path in sorted(packages_dir.glob("*.yaml")):
        doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        if not isinstance(doc, dict):
            continue
        if doc.get("kind") != "Package":
            continue
        name = str((doc.get("metadata") or {}).get("name") or "")
        examples = (doc.get("spec") or {}).get("appConfigExamples") or []
        content = None
        for example in examples:
            if not isinstance(example, dict):
                continue
            if example.get("content"):
                content = example["content"]
                if example.get("title") == "Default configuration":
                    break
        if name and isinstance(content, dict):
            configs[name] = content
    return configs


def ensure_doc(
    doc: dict[str, Any] | None,
    configs: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    out = dict(DEFAULT_DOC)
    if isinstance(doc, dict):
        if "includes" in doc:
            out["includes"] = doc["includes"]
        if "plugins" in doc:
            out["plugins"] = doc["plugins"]
        for key, value in doc.items():
            if key not in out:
                out[key] = value
    plugins = out.get("plugins")
    if not isinstance(plugins, list):
        plugins = []
        out["plugins"] = plugins
    for entry in plugins:
        if not isinstance(entry, dict):
            continue
        if entry.get("pluginConfig"):
            continue
        key = _layer_name(str(entry.get("package") or ""))
        if key in configs:
            entry["pluginConfig"] = configs[key]
    return out


def ensure_file(path: Path, catalog_index: Path) -> dict[str, Any]:
    configs = load_package_configs(catalog_index)
    if path.is_file():
        loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    else:
        loaded = None
        path.parent.mkdir(parents=True, exist_ok=True)
    out = ensure_doc(loaded, configs)
    path.write_text(
        yaml.safe_dump(
            out,
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            width=100,
        ),
        encoding="utf-8",
    )
    return out


def _self_test() -> None:
    import tempfile

    catalog = ROOT / "overlay" / "catalog-index"
    configs = load_package_configs(catalog)
    assert "ansible-plugin-backstage-apme" in configs, configs.keys()
    fe_cfg = configs["ansible-plugin-backstage-apme"]
    factories = fe_cfg["dynamicPlugins"]["frontend"]["ansible.plugin-backstage-apme"][
        "apiFactories"
    ]
    names = {item["importName"] for item in factories}
    assert names == {"apmeApiFactory", "gitRepositoriesExtensionsApiFactory"}, names

    empty = ensure_doc(None, configs)
    assert empty["plugins"] == []

    preserved = ensure_doc(
        {
            "includes": ["dynamic-plugins.default.yaml"],
            "plugins": [
                {
                    "package": (
                        "oci://quay.io/example/plugin-backstage-apme:dev"
                        "!ansible-plugin-backstage-apme"
                    ),
                    "disabled": False,
                }
            ],
        },
        configs,
    )
    assert preserved["includes"] == ["dynamic-plugins.default.yaml"]
    assert preserved["plugins"][0]["pluginConfig"] == fe_cfg

    already = {
        "plugins": [
            {
                "package": "oci://x!ansible-plugin-backstage-apme",
                "pluginConfig": {"keep": True},
            }
        ]
    }
    assert ensure_doc(already, configs)["plugins"][0]["pluginConfig"] == {"keep": True}

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "dynamic-plugins.extensions.yaml"
        ensure_file(path, catalog)
        created = yaml.safe_load(path.read_text(encoding="utf-8"))
        assert created["plugins"] == []
        path.write_text(
            yaml.safe_dump(
                {
                    "includes": [],
                    "plugins": [
                        {
                            "package": "oci://x!ansible-plugin-backstage-apme",
                            "disabled": False,
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        ensure_file(path, catalog)
        updated = yaml.safe_load(path.read_text(encoding="utf-8"))
        assert updated["plugins"][0]["pluginConfig"]["dynamicPlugins"]["frontend"]
    print("  ✓ ensure-extensions-yaml self-test")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--file",
        type=Path,
        required=not ("--self-test" in sys.argv),
        help="dynamic-plugins.extensions.yaml to create or update",
    )
    parser.add_argument(
        "--catalog-index",
        type=Path,
        default=DEFAULT_CATALOG,
        help="overlay/catalog-index root (Package YAML with appConfigExamples)",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run built-in checks and exit",
    )
    args = parser.parse_args()
    if args.self_test:
        _self_test()
        return 0
    ensure_file(args.file, args.catalog_index)
    print(f"Wrote {args.file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
