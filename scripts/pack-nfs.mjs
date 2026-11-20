import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import {
  resolveProfile,
  profilePaths,
  deploymentPlugins,
} from "./nfs-composition.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repo = process.env.PLUGIN_REPO;
if (!repo) throw new Error("PLUGIN_REPO required");
const yaml = createRequire(path.join(repo, "package.json"))("js-yaml");
const dev = yaml.load(
  fs.readFileSync(path.join(root, profilePaths(resolveProfile()).dev), "utf8")
);
const destination = path.join(root, "local-plugins/portal-nfs");
fs.mkdirSync(destination, { recursive: true });
for (const entry of dev.plugins) {
  if (!entry.package.startsWith("./local-plugins/portal-nfs/")) continue;
  const name = path.basename(entry.package);
  const selected = deploymentPlugins().find(([, plugin]) => plugin === name);
  if (!selected)
    throw new Error(`Plugin is not in the selected composition: ${name}`);
  const source = path.join(
    repo,
    "workspaces",
    selected[0],
    "plugins",
    name,
    "dist-dynamic"
  );
  if (!fs.existsSync(path.join(source, "package.json")))
    throw new Error(`Missing selected export: ${name}`);
  const result = spawnSync(
    "npm",
    ["pack", "--ignore-scripts", "--pack-destination", destination],
    { cwd: source, stdio: "inherit" }
  );
  if (result.status !== 0) throw new Error(`Packing failed: ${name}`);
}
console.log(
  "Packed native workspace plugins without deleting existing archives or user data."
);
