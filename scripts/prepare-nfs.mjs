import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import {
  resolveProfile,
  deploymentPlugins,
  profilePaths,
  platformEntries,
} from "./nfs-composition.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repo = process.env.PLUGIN_REPO;
const packedMode = process.env.NFS_PACKAGE_MODE === "packed";
if (!repo || !fs.existsSync(path.join(repo, "workspaces")))
  throw new Error(
    "PLUGIN_REPO must point to the development workspace checkout"
  );
const require = createRequire(path.join(repo, "package.json"));
const yaml = require("js-yaml");
export const profile = resolveProfile();
export const plugins = deploymentPlugins();
const paths = profilePaths(profile, packedMode);
const withApme = plugins.some(
  ([workspace, name]) => workspace === "apme" && name === "backstage-apme"
);
const dump = (value) => yaml.dump(value, { lineWidth: -1, noRefs: true });
const save = (relative, value) =>
  fs.writeFileSync(path.join(root, relative), dump(value));
const config = yaml.load(
  fs.readFileSync(path.join(root, "overlay/app-config.portal.yaml"), "utf8")
);
// RHDH 2.1 discovers frontend features, not legacy routes/mountPoints/API factories.
delete config.dynamicPlugins;
delete config.auth.signInPage;
// Keep the existing real-AAP settings untouched; this deployment tests local mock auth.
config.ansible.rhaap.baseUrl = "http://aap-mock:8099";
config.ansible.apme = {
  ...config.ansible.apme,
  enabled: withApme,
  baseUrl:
    process.env.APME_BASE_URL ||
    config.ansible.apme?.baseUrl ||
    "http://host.containers.internal:8080",
};
config.ansible.rhaap.token = "local-mock-token";
for (const environment of ["development", "production"]) {
  Object.assign(config.auth.providers.rhaap[environment], {
    host: "http://localhost:8099",
    tokenHost: "http://aap-mock:8099",
    clientId: "portal-local-mock",
    clientSecret: "portal-local-mock-secret",
  });
}
config.app.extensions = [
  { "sign-in-page:app": false },
  { "sign-in-page:app/rhaap": true },
  { "nav-content:app/sidebar": false },
  { "nav-content:app/portal": true },
];
// Mock acceptance uses one configured organization; real memberships stay server-owned.
config.catalog.providers.rhaap.development.orgs = ["Default"];
config.catalog.providers.rhaap.development.multiOrgEnabled = false;
config.portal = {
  ...config.portal,
  entitlements: config.portal?.entitlements ?? {
    grants: withApme
      ? [{ id: "apme.scanning", organizations: ["default"] }]
      : [],
  },
};
// Filter navigation only: preserve platform APIs and direct compatibility routes.
config.portal.navigation = {
  topOffset: 64,
  items: [
    { id: "templates", path: "/self-service", title: "Templates" },
    { id: "history", path: "/self-service/create/tasks", title: "History" },
    {
      id: "execution-environments",
      path: "/self-service/ee",
      title: "Execution Environments",
    },
    {
      id: "collections",
      path: "/self-service/collections",
      title: "Collections",
    },
    {
      id: "repositories",
      path: "/self-service/repositories",
      title: "Git repositories",
    },
    {
      id: "administration",
      title: "Administration",
      placement: "bottom",
      children: [{ id: "rbac", path: "/rbac", title: "RBAC" }],
    },
    {
      id: "settings",
      path: "/settings",
      title: "Settings",
      placement: "bottom",
    },
  ],
  ...config.portal.navigation,
};
config.permission.rbac.pluginsWithPermission = [
  "catalog",
  "scaffolder",
  "permission",
  "portal-operations",
];
if (!withApme) {
  config.catalog.locations = (config.catalog.locations ?? []).filter(
    (location) => !location.target?.includes("apme-register-git-repository")
  );
}
save(paths.config, config);
const mounts = plugins.map(
  ([workspace, name]) =>
    `\${PLUGIN_REPO}/workspaces/${workspace}/plugins/${name}/dist-dynamic:/opt/app-root/src/local-plugins/portal-nfs/${name}:ro,z`
);
// Distinct installation roots prevent omitted plugins surviving a profile change.
const installed = `./${paths.installed}`;
const services = {
  "aap-mock": {
    environment: {
      AAP_PUBLIC_URL: "http://localhost:8099",
      AAP_TOKEN: "local-mock-token",
      OAUTH_CLIENT_ID: "portal-local-mock",
      OAUTH_CLIENT_SECRET: "portal-local-mock-secret",
    },
  },
  "install-dynamic-plugins": {
    environment: { NODE_TLS_REJECT_UNAUTHORIZED: "1" },
    volumes: [
      `${installed}:/dynamic-plugins-root:z`,
      `../${
        packedMode ? paths.packed : paths.dev
      }:/opt/app-root/src/configs/dynamic-plugins/dynamic-plugins.override.yaml:ro,z`,
      ...(packedMode
        ? [
            "../local-plugins/portal-nfs:/opt/app-root/src/local-plugins/portal:ro,z",
          ]
        : mounts),
    ],
  },
  rhdh: {
    depends_on: {
      db: { condition: "service_healthy" },
      "aap-mock": { condition: "service_healthy" },
    },
    networks: ["default"],
    environment: { NODE_TLS_REJECT_UNAUTHORIZED: "1" },
    volumes: [
      `${installed}:/opt/app-root/src/dynamic-plugins-root:z`,
      `../${paths.config}:/opt/app-root/src/configs/app-config/app-config.local.yaml:ro,z`,
      ...(packedMode ? [] : mounts),
    ],
  },
};
save(paths.compose, {
  services,
  networks: {
    default: {},
  },
});
const entries = plugins.map(([, name]) => ({
  package: `./local-plugins/portal-nfs/${name}`,
  disabled: false,
}));
entries[0].sharedPackages = [
  "@ansible/portal-extension-api",
  "@ansible/portal-extension-host",
];
// Stock RHDH RBAC provides its own native frontend feature. Keep the existing
// permission policy/admin identities; installing the UI does not add grants.
const dev = {
  includes: ["dynamic-plugins.default.yaml"],
  plugins: [...entries, ...platformEntries],
};
save(paths.dev, dev);
const packed = entries.map((entry) => {
  const name = entry.package.split("/").at(-1);
  const [workspace] = plugins.find(([, plugin]) => plugin === name);
  const pkg = JSON.parse(
    fs.readFileSync(
      path.join(
        repo,
        "workspaces",
        workspace,
        "plugins",
        name,
        "dist-dynamic/package.json"
      )
    )
  );
  return {
    ...entry,
    package: `./local-plugins/portal/${pkg.name
      .replace(/^@/, "")
      .replaceAll("/", "-")}-${pkg.version}.tgz`,
  };
});
save(paths.packed, {
  ...dev,
  plugins: [...packed, ...platformEntries],
});
fs.mkdirSync(path.join(root, "rhdh-local", installed), { recursive: true });
const marker = path.join(
  root,
  "rhdh-local",
  installed,
  "app-config.dynamic-plugins.yaml"
);
if (!fs.existsSync(marker)) fs.writeFileSync(marker, "{}\n");
if (withApme) {
  const template = path.join(
    repo,
    "workspaces/apme/plugins/backstage-apme/templates/apme-register-git-repository"
  );
  fs.cpSync(
    template,
    path.join(root, "rhdh-local/configs/catalog/apme-register-git-repository"),
    { recursive: true }
  );
}
console.log(
  `Prepared ${profile} native deployment configuration and matching dev/tarball contracts; no catalog or APME data removed.`
);
