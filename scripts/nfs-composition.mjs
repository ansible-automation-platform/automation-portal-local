import { pathToFileURL } from "node:url";
import { createRequire } from "node:module";
import { createHash } from "node:crypto";
import path from "node:path";

/** Native deployment selection. Libraries are built through their consumers. */
export const basePlugins = [
  ["portal-core", "portal-core"],
  ["portal-core", "portal-rhdh"],
  ["aap", "aap-app-auth"],
  ["aap", "auth-backend-module-rhaap-provider"],
  ["aap", "catalog-backend-module-rhaap"],
  ["aap", "catalog-backend-module-rhaap-user-provisioner"],
  ["portal-core", "portal-operations-backend"],
  ["portal-core", "portal-health-backend"],
];

/** Match the Makefile's AAP_MOCK flag without reading or copying credentials. */
export function usesAapMock(env = process.env) {
  return !/^(0|false|no|off)$/i.test(env.AAP_MOCK ?? "1");
}

export function resolveProfile(env = process.env) {
  const portalOnly = /^(1|true|yes|on)$/i.test(env.PORTAL_ONLY ?? "0");
  const profile = env.PORTAL_PROFILE || (portalOnly ? "scaffolder" : "full");
  if (!["full", "scaffolder", "core"].includes(profile)) {
    throw new Error(
      `Unknown PORTAL_PROFILE '${profile}'; use full, scaffolder or core`
    );
  }
  if (portalOnly && profile === "full") {
    throw new Error("PORTAL_PROFILE=full conflicts with PORTAL_ONLY=1");
  }
  return profile;
}

export function additionalPluginNames(env = process.env) {
  const names = (env.PORTAL_EXTRA_PLUGINS ?? "")
    .split(/[\s,]+/)
    .filter(Boolean);
  if (new Set(names).size !== names.length)
    throw new Error("Duplicate PORTAL_EXTRA_PLUGINS package");
  return names.sort();
}

export function selectPlugins(
  profile,
  extras = [],
  repo = process.env.PLUGIN_REPO
) {
  if (!["full", "scaffolder", "core"].includes(profile)) {
    throw new Error(`Unknown native deployment profile '${profile}'`);
  }
  const selected = [
    ...basePlugins,
    ...(profile !== "core"
      ? [
          ["portal-scaffolder", "portal-scaffolder"],
          ["aap", "scaffolder-backend-module-backstage-rhaap"],
        ]
      : []),
    ...(profile === "full"
      ? [
          ["apme", "backstage-apme"],
          ["apme", "catalog-backend-module-apme"],
          ["apme", "scaffolder-backend-module-apme"],
        ]
      : []),
  ];
  if (!extras.length) return selected;
  if (!repo)
    throw new Error("PLUGIN_REPO is required for additional workspace plugins");
  const { selectedWorkspacePlugins } = createRequire(
    path.join(repo, "package.json")
  )("./scripts/portal-development-workspaces.cjs");
  for (const plugin of selectedWorkspacePlugins(repo, extras, {
    dynamic: true,
  })) {
    const parts = plugin.relativeDir.split(path.sep);
    if (
      parts.length !== 4 ||
      parts[0] !== "workspaces" ||
      parts[2] !== "plugins"
    ) {
      throw new Error(
        `${plugin.packageJson.name} must live under workspaces/<workspace>/plugins/<plugin>`
      );
    }
    const pair = [parts[1], parts[3]];
    if (
      !selected.some(
        ([workspace, name]) => workspace === pair[0] && name === pair[1]
      )
    )
      selected.push(pair);
  }
  const names = selected.map(([, name]) => name);
  if (new Set(names).size !== names.length) {
    throw new Error(
      "Selected workspace plugins must have unique directory names for dynamic artifact mounts"
    );
  }
  if (
    names.includes("backstage-apme") &&
    !names.includes("portal-scaffolder")
  ) {
    throw new Error(
      "APME's current repository UI needs portal-scaffolder; use the full profile or include its host explicitly"
    );
  }
  return selected;
}

export function deploymentPlugins(env = process.env) {
  return selectPlugins(
    resolveProfile(env),
    additionalPluginNames(env),
    env.PLUGIN_REPO
  );
}

export const platformEntries = [
  {
    package:
      "oci://quay.io/rhdh/backstage-community-plugin-rbac@sha256:550067cea6abbb221deb3e1d14d8ef20fdc220c4607f7e038949ed89b20924ae",
    disabled: false,
  },
];

export function profilePaths(profile, packed = false, env = process.env) {
  const extras = additionalPluginNames(env);
  const selection = extras.length
    ? `-${createHash("sha256")
        .update(JSON.stringify(extras))
        .digest("hex")
        .slice(0, 12)}`
    : "";
  const suffix = `${profile === "full" ? "" : `.${profile}`}${selection}`;
  return {
    config: `overlay/app-config.portal.nfs${suffix}.yaml`,
    compose: `overlay/compose.portal.nfs${suffix}.yaml`,
    dev: `overlay/dynamic-plugins.portal.nfs${suffix}.dev.yaml`,
    packed: `overlay/dynamic-plugins.portal.nfs${suffix}.yaml`,
    installed: `dynamic-plugins-root-nfs${packed ? "-packed" : ""}${
      profile === "full" ? "" : `-${profile}`
    }${selection}`,
  };
}

// Also used by the shell exporter, so export/install selection cannot drift.
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  for (const [workspace, name] of deploymentPlugins()) {
    console.log(`${workspace}/${name}`);
  }
}
