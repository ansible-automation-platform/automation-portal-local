import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { test } from "node:test";
import {
  resolveProfile,
  selectPlugins,
  profilePaths,
  additionalPluginNames,
  deploymentPlugins,
  usesAapMock,
} from "./nfs-composition.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repo = process.env.PLUGIN_REPO;
if (!repo) throw new Error("PLUGIN_REPO required for native composition tests");
const yaml = createRequire(path.join(repo, "package.json"))("js-yaml");

test("AAP auth selection matches the existing Makefile flag", () => {
  assert.equal(usesAapMock({}), true);
  for (const value of ["0", "false", "NO", "off"])
    assert.equal(usesAapMock({ AAP_MOCK: value }), false);
  for (const value of ["1", "true", "yes", "ON", ""])
    assert.equal(usesAapMock({ AAP_MOCK: value }), true);
});

test("profile selection preserves default and PORTAL_ONLY compatibility", () => {
  assert.equal(resolveProfile({}), "full");
  assert.equal(resolveProfile({ PORTAL_PROFILE: "" }), "full");
  for (const value of ["1", "true", "yes", "ON"]) {
    assert.equal(resolveProfile({ PORTAL_ONLY: value }), "scaffolder");
    assert.equal(
      resolveProfile({ PORTAL_ONLY: value, PORTAL_PROFILE: "core" }),
      "core"
    );
    assert.throws(
      () => resolveProfile({ PORTAL_ONLY: value, PORTAL_PROFILE: "full" }),
      /conflicts/
    );
  }
  assert.throws(
    () => resolveProfile({ PORTAL_PROFILE: "typo" }),
    /Unknown PORTAL_PROFILE/
  );
  assert.throws(
    () => selectPlugins("typo"),
    /Unknown native deployment profile/
  );
});

test("selection excludes artifacts, not merely sidebar links", () => {
  assert.equal(selectPlugins("full").length, 13);
  assert.equal(selectPlugins("scaffolder").length, 10);
  assert.equal(selectPlugins("core").length, 8);
  for (const profile of ["full", "scaffolder", "core"]) {
    const names = selectPlugins(profile).map(([, name]) => name);
    assert.ok(names.includes("aap-app-auth"));
    assert.ok(names.includes("portal-rhdh"));
    assert.ok(names.includes("portal-operations-backend"));
    assert.equal(names.includes("portal-scaffolder"), profile !== "core");
    assert.equal(names.includes("backstage-apme"), profile === "full");
    assert.ok(!names.includes("portal-extension-api"));
    assert.ok(!names.includes("portal-extension-host"));
    for (const [workspace, name] of selectPlugins(profile))
      assert.ok(
        fs.existsSync(
          path.join(
            repo,
            "workspaces",
            workspace,
            "plugins",
            name,
            "package.json"
          )
        ),
        `Selected plugin must exist in the current checkout: ${workspace}/${name}`
      );
  }
});

test("installation roots isolate profiles and packaging modes without deleting old data", () => {
  const roots = ["full", "scaffolder", "core"].flatMap((profile) =>
    [false, true].map((packed) => profilePaths(profile, packed).installed)
  );
  assert.equal(new Set(roots).size, 6);
  assert.equal(profilePaths("full").installed, "dynamic-plugins-root-nfs");
  assert.equal(
    profilePaths("full", true).installed,
    "dynamic-plugins-root-nfs-packed"
  );
});

test("additional workspace plugins extend presets without changing the host inventory", (t) => {
  const temporary = fs.mkdtempSync(
    path.join(os.tmpdir(), "portal-extra-plugins-test-")
  );
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  fs.mkdirSync(path.join(temporary, "scripts"));
  fs.copyFileSync(
    path.join(repo, "scripts/portal-development-workspaces.cjs"),
    path.join(temporary, "scripts/portal-development-workspaces.cjs")
  );
  fs.writeFileSync(
    path.join(temporary, "package.json"),
    JSON.stringify({ workspaces: ["workspaces/*/plugins/*"] })
  );
  function plugin(folder, name, role, extra = {}) {
    const directory = path.join(temporary, "workspaces/custom/plugins", folder);
    fs.mkdirSync(directory, { recursive: true });
    fs.writeFileSync(
      path.join(directory, "package.json"),
      JSON.stringify({
        name,
        backstage: { role },
        exports: { "./alpha": "./src/alpha.tsx" },
        scripts: { "export-dynamic": "yarn run -T rhdh-cli plugin export" },
        ...extra,
      })
    );
  }
  plugin("scanner", "@team/scanner", "frontend-plugin");
  plugin("worker", "@team/worker", "backend-plugin");
  plugin("sdk", "@team/sdk", "web-library");
  plugin("legacy", "@team/legacy", "frontend-plugin", { exports: {} });
  plugin("no-export", "@team/no-export", "backend-plugin", { scripts: {} });
  const env = {
    PLUGIN_REPO: temporary,
    PORTAL_PROFILE: "core",
    PORTAL_EXTRA_PLUGINS: "@team/worker,@team/scanner",
  };
  assert.deepEqual(additionalPluginNames(env), [
    "@team/scanner",
    "@team/worker",
  ]);
  assert.deepEqual(deploymentPlugins(env).slice(8), [
    ["custom", "scanner"],
    ["custom", "worker"],
  ]);
  assert.equal(
    deploymentPlugins(env).some(([, name]) => name === "portal-scaffolder"),
    false
  );
  assert.deepEqual(
    deploymentPlugins({ ...env, PORTAL_EXTRA_PLUGINS: "" }),
    selectPlugins("core")
  );
  const selectedPaths = profilePaths("core", false, env);
  assert.notEqual(
    selectedPaths.installed,
    profilePaths("core", false, {}).installed
  );
  assert.deepEqual(
    selectedPaths,
    profilePaths("core", false, {
      ...env,
      PORTAL_EXTRA_PLUGINS: "@team/scanner @team/worker",
    })
  );
  assert.notEqual(
    selectedPaths.installed,
    profilePaths("core", false, {
      ...env,
      PORTAL_EXTRA_PLUGINS: "@team/scanner",
    }).installed
  );
  assert.throws(
    () =>
      additionalPluginNames({
        PORTAL_EXTRA_PLUGINS: "@team/scanner,@team/scanner",
      }),
    /Duplicate/
  );
  for (const [name, expected] of [
    ["@team/unknown", /Unknown workspace/],
    ["@team/sdk", /unsupported standalone/],
    ["@team/legacy", /native .*alpha/],
    ["@team/no-export", /export-dynamic/],
    ["https://example.test/plugin", /package names/],
    ["../outside", /package names/],
  ]) {
    assert.throws(
      () => deploymentPlugins({ ...env, PORTAL_EXTRA_PLUGINS: name }),
      expected
    );
  }
});

const scenarios = ["full", "scaffolder", "core"].flatMap((profile) =>
  [true, false].map((mockAap) => ({ profile, mockAap }))
);
for (const { profile, mockAap } of scenarios) {
  test(`generated ${profile} ${mockAap ? "mock" : "real-AAP"} workspace/packed configuration matches the selected exports`, (t) => {
    const temporary = fs.mkdtempSync(
      path.join(os.tmpdir(), "portal-composition-test-")
    );
    t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
    const fixtureRepo = path.join(temporary, "plugin-repo");
    fs.mkdirSync(path.join(temporary, "scripts"), { recursive: true });
    fs.mkdirSync(path.join(temporary, "overlay"));
    fs.mkdirSync(fixtureRepo);
    fs.writeFileSync(path.join(fixtureRepo, "package.json"), "{}");
    fs.symlinkSync(
      path.join(repo, "node_modules"),
      path.join(fixtureRepo, "node_modules"),
      "dir"
    );
    for (const script of [
      "prepare-nfs.mjs",
      "check-nfs-parity.mjs",
      "nfs-composition.mjs",
      "start-nfs.sh",
      "refresh-nfs-cache.mjs",
    ]) {
      fs.copyFileSync(
        path.join(root, "scripts", script),
        path.join(temporary, "scripts", script)
      );
    }
    for (const [workspace, name] of selectPlugins(profile)) {
      const output = path.join(
        fixtureRepo,
        "workspaces",
        workspace,
        "plugins",
        name,
        "dist-dynamic"
      );
      fs.mkdirSync(output, { recursive: true });
      fs.writeFileSync(
        path.join(path.dirname(output), "package.json"),
        JSON.stringify({
          scripts: { "export-dynamic": "yarn run -T rhdh-cli plugin export" },
        })
      );
      fs.writeFileSync(
        path.join(output, "package.json"),
        JSON.stringify({
          name: `@ansible/${name}-dynamic`,
          version: "0.1.0",
        })
      );
    }
    const template = path.join(
      fixtureRepo,
      "workspaces/apme/plugins/backstage-apme/templates/apme-register-git-repository"
    );
    fs.mkdirSync(template, { recursive: true });
    fs.writeFileSync(path.join(template, "template.yaml"), "kind: Template\n");
    fs.writeFileSync(
      path.join(temporary, "overlay/app-config.portal.yaml"),
      yaml.dump({
        app: {},
        ansible: {
          rhaap: { baseUrl: "${AAP_HOST_URL}", token: "${AAP_TOKEN}" },
          apme: {},
        },
        auth: {
          environment: "production",
          providers: {
            rhaap: {
              development: {
                host: "${AAP_PUBLIC_URL}",
                clientId: "${OAUTH_CLIENT_ID}",
                clientSecret: "${OAUTH_CLIENT_SECRET}",
              },
              production: {
                host: "${AAP_PUBLIC_URL}",
                tokenHost: "https://tokens.example.test",
                clientId: "${OAUTH_CLIENT_ID}",
                clientSecret: "${OAUTH_CLIENT_SECRET}",
              },
            },
          },
        },
        catalog: {
          providers: {
            rhaap: {
              development: {
                orgs: ["Default", "Engineering"],
                multiOrgEnabled: true,
              },
            },
          },
          locations: [
            { target: "/configs/apme-register-git-repository/template.yaml" },
          ],
        },
        permission: { rbac: {} },
      })
    );
    const env = {
      ...process.env,
      PLUGIN_REPO: fixtureRepo,
      PORTAL_PROFILE: profile,
      PORTAL_ONLY: "0",
      APME_BASE_URL: "https://gateway.example.test:8443",
      NFS_PACKAGE_MODE: "workspace",
      AAP_MOCK: mockAap ? "1" : "0",
      COMPOSE_PROFILES: "mock,stale-profile",
      TEST_EXPECTED_PROFILES: mockAap ? "mock" : "",
      OAUTH_CLIENT_SECRET: "must-not-be-inlined",
    };
    function run(script) {
      const result = spawnSync(
        process.execPath,
        [path.join(temporary, "scripts", script)],
        { env, encoding: "utf8" }
      );
      assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    }
    run("prepare-nfs.mjs");
    run("check-nfs-parity.mjs");
    const paths = profilePaths(profile);
    const load = (relative) =>
      yaml.load(fs.readFileSync(path.join(temporary, relative), "utf8"));
    const config = load(paths.config);
    for (const entry of [
      { "gh-component:global-header/self-service-button": false },
      { "gh-menu-item:global-header/logout": mockAap },
      { "app-profile-menu-item:app/aap-logout": !mockAap },
    ])
      assert.ok(
        config.app.extensions.some(
          (item) => JSON.stringify(item) === JSON.stringify(entry)
        )
      );
    assert.equal(config.portal.development, undefined);
    assert.equal(config.auth.environment, "production");
    const providers = config.auth.providers.rhaap;
    if (mockAap) {
      assert.equal(config.ansible.rhaap.baseUrl, "http://aap-mock:8099");
      assert.equal(providers.production.clientId, "portal-local-mock");
      assert.deepEqual(config.catalog.providers.rhaap.development.orgs, [
        "Default",
      ]);
      assert.equal(
        config.catalog.providers.rhaap.development.multiOrgEnabled,
        false
      );
    } else {
      assert.deepEqual(config.ansible.rhaap, {
        baseUrl: "${AAP_HOST_URL}",
        token: "${AAP_TOKEN}",
      });
      assert.equal(providers.development.tokenHost, "${AAP_HOST_URL}");
      assert.equal(
        providers.production.tokenHost,
        "https://tokens.example.test"
      );
      assert.equal(providers.production.host, "${AAP_PUBLIC_URL}");
      assert.equal(providers.production.clientId, "${OAUTH_CLIENT_ID}");
      assert.equal(providers.production.clientSecret, "${OAUTH_CLIENT_SECRET}");
      assert.deepEqual(config.catalog.providers.rhaap.development.orgs, [
        "Default",
        "Engineering",
      ]);
      assert.equal(
        config.catalog.providers.rhaap.development.multiOrgEnabled,
        true
      );
      assert.ok(
        !fs
          .readFileSync(path.join(temporary, paths.config), "utf8")
          .includes(env.OAUTH_CLIENT_SECRET)
      );
    }
    assert.equal(config.ansible.apme.enabled, profile === "full");
    assert.equal(
      config.ansible.apme.baseUrl,
      "https://gateway.example.test:8443"
    );
    assert.equal(config.catalog.locations.length, profile === "full" ? 1 : 0);
    const compose = load(paths.compose);
    const mounts = compose.services.rhdh.volumes.join("\n");
    assert.equal(mounts.includes("/portal-scaffolder/"), profile !== "core");
    assert.equal(mounts.includes("/backstage-apme/"), profile === "full");
    assert.deepEqual(compose.services.rhdh.networks, ["default"]);
    assert.deepEqual(compose.services.rhdh.depends_on.db, {
      condition: "service_healthy",
    });
    assert.deepEqual(
      compose.services.rhdh.depends_on["aap-mock"],
      mockAap
        ? {
            condition: "service_healthy",
          }
        : undefined
    );
    assert.equal(Boolean(compose.services["aap-mock"]), mockAap);
    const before = fs.readFileSync(path.join(temporary, paths.dev), "utf8");
    const bad = load(paths.dev);
    bad.plugins.push({
      package: "./local-plugins/portal-nfs/unselected",
      disabled: false,
    });
    fs.writeFileSync(path.join(temporary, paths.dev), yaml.dump(bad));
    const rejected = spawnSync(
      process.execPath,
      [path.join(temporary, "scripts/check-nfs-parity.mjs")],
      { env, encoding: "utf8" }
    );
    assert.notEqual(
      rejected.status,
      0,
      "Parity must reject unselected artifacts"
    );
    fs.writeFileSync(path.join(temporary, paths.dev), before);
    env.NFS_PACKAGE_MODE = "packed";
    run("prepare-nfs.mjs");
    run("check-nfs-parity.mjs");
    const packedMounts = load(paths.compose).services.rhdh.volumes.join("\n");
    assert.ok(!packedMounts.includes("/dist-dynamic:"));
    assert.ok(packedMounts.includes(profilePaths(profile, true).installed));

    // Metadata refresh follows frontend roles, not the @ansible namespace.
    const installed = path.join(
      temporary,
      "rhdh-local",
      profilePaths(profile, true).installed
    );
    for (const [name, role] of [
      ["team-scanner", "frontend-plugin"],
      ["team-backend", "backend-plugin"],
    ]) {
      const directory = path.join(installed, name);
      fs.mkdirSync(path.join(directory, "dist"), { recursive: true });
      fs.writeFileSync(
        path.join(directory, "package.json"),
        JSON.stringify({ backstage: { role } })
      );
      const entry = path.join(directory, "dist/remoteEntry.js");
      fs.writeFileSync(entry, "entry");
      fs.utimesSync(entry, new Date(0), new Date(0));
    }
    run("refresh-nfs-cache.mjs");
    assert.ok(
      fs.statSync(path.join(installed, "team-scanner/dist/remoteEntry.js"))
        .mtimeMs > 0
    );
    assert.equal(
      fs.statSync(path.join(installed, "team-backend/dist/remoteEntry.js"))
        .mtimeMs,
      0
    );

    // Exercise the real startup shell with local command doubles. No containers
    // are contacted; assertions protect the scope of runtime recreation.
    const bin = path.join(temporary, "bin");
    fs.mkdirSync(bin);
    const calls = path.join(temporary, "podman-calls.jsonl");
    fs.writeFileSync(path.join(bin, "make"), "#!/bin/sh\nexit 0\n", {
      mode: 0o755,
    });
    fs.writeFileSync(
      path.join(bin, "yarn"),
      `#!${process.execPath}
require('node:fs').appendFileSync(process.env.TEST_EXPORT_CALLS, JSON.stringify(process.argv.slice(2)) + '\\n');
`,
      { mode: 0o755 }
    );
    fs.writeFileSync(
      path.join(bin, "podman"),
      `#!${process.execPath}
const fs = require('node:fs');
const args = process.argv.slice(2);
if (process.env.COMPOSE_PROFILES !== process.env.TEST_EXPECTED_PROFILES) process.exit(2);
fs.appendFileSync(process.env.TEST_CALLS, JSON.stringify(args) + '\\n');
if (args[0] === 'inspect') console.log(process.env.TEST_OWNER);
if (args[0] === 'wait') console.log(process.env.TEST_INSTALLER_EXIT || '0');
`,
      { mode: 0o755 }
    );
    Object.assign(env, {
      PATH: `${bin}:${process.env.PATH}`,
      TEST_CALLS: calls,
      TEST_EXPORT_CALLS: path.join(temporary, "export-calls.jsonl"),
      TEST_OWNER: path.join(temporary, "rhdh-local"),
      SKIP_EXPORT: "0",
      PORTAL_ENV_LOADED: "1",
      NFS_PREPARE_ONLY: "0",
      AAP_MOCK: mockAap ? "1" : "0",
      NFS_PACKAGE_MODE: "workspace",
    });
    const start = () =>
      spawnSync("bash", [path.join(temporary, "scripts/start-nfs.sh")], {
        env,
        encoding: "utf8",
      });
    const started = start();
    assert.equal(started.status, 0, `${started.stdout}\n${started.stderr}`);
    const exportCalls = fs
      .readFileSync(env.TEST_EXPORT_CALLS, "utf8")
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line));
    assert.equal(exportCalls.length, selectPlugins(profile).length);
    assert.ok(
      exportCalls.every(
        (args) =>
          JSON.stringify(args) === JSON.stringify(["run", "export-dynamic"])
      )
    );
    const readCalls = () =>
      fs
        .readFileSync(calls, "utf8")
        .trim()
        .split("\n")
        .map((line) => JSON.parse(line));
    assert.deepEqual(
      readCalls().filter((args) => args[0] === "rm"),
      [
        ["rm", "--force", "rhdh"],
        ["rm", "--force", "rhdh-plugins-installer"],
      ]
    );
    assert.ok(
      readCalls().some(
        (args) => args.includes("--no-recreate") && args.at(-1) === "db"
      )
    );
    assert.equal(
      readCalls().some(
        (args) => args.includes("--no-deps") && args.includes("aap-mock")
      ),
      mockAap
    );
    if (!mockAap)
      assert.ok(
        readCalls().every(
          (args) => !args.includes("aap-mock") && !args.includes("mock")
        )
      );
    assert.ok(
      readCalls().some(
        (args) =>
          args[0] === "compose" &&
          args.at(-1) === "rhdh" &&
          args.includes("--no-deps")
      )
    );
    fs.writeFileSync(calls, "");
    env.TEST_OWNER = "/another-checkout/rhdh-local";
    const refused = start();
    assert.notEqual(refused.status, 0);
    assert.match(refused.stderr, /Refusing to replace/);
    assert.equal(
      readCalls().some((args) => args[0] === "rm"),
      false
    );
    fs.writeFileSync(calls, "");
    env.TEST_OWNER = path.join(temporary, "rhdh-local");
    env.TEST_INSTALLER_EXIT = "1";
    const failedInstaller = start();
    assert.notEqual(failedInstaller.status, 0);
    assert.match(
      failedInstaller.stderr + failedInstaller.stdout,
      /Plugin installer failed/
    );
    assert.equal(
      readCalls().some(
        (args) => args[0] === "compose" && args.at(-1) === "rhdh"
      ),
      false
    );
  });
}
