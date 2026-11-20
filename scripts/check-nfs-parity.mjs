import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
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
if (!repo) throw new Error("PLUGIN_REPO required");
const yaml = createRequire(path.join(repo, "package.json"))("js-yaml");
const profile = resolveProfile();
const selected = deploymentPlugins();
const paths = profilePaths(profile);
const dev = yaml.load(fs.readFileSync(path.join(root, paths.dev), "utf8"));
const tar = yaml.load(fs.readFileSync(path.join(root, paths.packed), "utf8"));
const contract = (doc) => ({
  ...doc,
  plugins: doc.plugins.map(({ package: location, ...entry }) => entry),
});
assert.deepEqual(
  contract(dev),
  contract(tar),
  "NFS dev/tarball host contracts differ"
);
assert.deepEqual(
  dev.plugins.map((plugin) => plugin.package),
  [
    ...selected.map(([, name]) => `./local-plugins/portal-nfs/${name}`),
    ...platformEntries.map((entry) => entry.package),
  ],
  "Installed native plugins must match the selected profile exactly"
);
assert.equal(
  new Set(dev.plugins.map((plugin) => plugin.package)).size,
  dev.plugins.length
);
assert.equal(
  new Set(tar.plugins.map((plugin) => plugin.package)).size,
  tar.plugins.length,
  "Packed artifact paths must be unique"
);
assert.deepEqual(dev.plugins[0].sharedPackages, [
  "@ansible/portal-extension-api",
  "@ansible/portal-extension-host",
]);
for (const [index, [workspace, name]] of selected.entries()) {
  const pkg = JSON.parse(
    fs.readFileSync(
      path.join(
        repo,
        "workspaces",
        workspace,
        "plugins",
        name,
        "dist-dynamic/package.json"
      ),
      "utf8"
    )
  );
  const packed = `./local-plugins/portal/${pkg.name
    .replace(/^@/, "")
    .replaceAll("/", "-")}-${pkg.version}.tgz`;
  assert.equal(
    tar.plugins[index].package,
    packed,
    `Packed artifact mismatch for ${name}`
  );
}
assert.deepEqual(
  tar.plugins.slice(selected.length),
  platformEntries,
  "Platform plugin selection differs"
);
for (const entry of dev.plugins) {
  assert.equal(entry.disabled, false, "Selected plugin unexpectedly disabled");
  assert.equal(
    entry.pluginConfig?.dynamicPlugins?.frontend,
    undefined,
    "Legacy frontend wiring in native deployment"
  );
}
console.log(
  `NFS ${profile} dev/tarball host contracts match (${selected.length} Portal plugins plus stock RBAC).`
);
