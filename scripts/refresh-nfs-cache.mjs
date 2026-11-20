import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveProfile, profilePaths } from "./nfs-composition.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const installed = path.join(
  root,
  "rhdh-local",
  profilePaths(resolveProfile(), process.env.NFS_PACKAGE_MODE === "packed")
    .installed
);
const now = new Date();
let refreshed = 0;
// Installer archives have reproducible timestamps. Express's weak ETag uses
// file size + mtime, so same-sized replacements can reuse a stale validator.
// Refresh only mutable MF entry metadata, never hashed assets or user data.
for (const name of fs.readdirSync(installed)) {
  const manifestPath = path.join(installed, name, "package.json");
  if (!fs.existsSync(manifestPath)) continue;
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (
    !["frontend-plugin", "frontend-plugin-module"].includes(
      manifest.backstage?.role
    )
  )
    continue;
  for (const file of ["remoteEntry.js", "mf-manifest.json", "mf-stats.json"]) {
    const target = path.join(installed, name, "dist", file);
    if (!fs.existsSync(target)) continue;
    fs.utimesSync(target, now, now);
    refreshed++;
  }
}
console.log(
  `Refreshed cache validators for ${refreshed} native Portal metadata files.`
);
