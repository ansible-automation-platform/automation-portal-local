/**
 * Upstream remotes for on-demand collection resolve.
 * Order is cascade priority: certified → validated → galaxy.
 */

export function getRemotes(env = process.env) {
  const hubToken = (env.AAP_MOCK_HUB_TOKEN || '').trim();
  const hubBase = (
    env.AAP_MOCK_HUB_BASE || 'https://console.redhat.com/api/automation-hub'
  ).replace(/\/$/, '');
  const galaxyBase = (
    env.AAP_MOCK_GALAXY_BASE || 'https://galaxy.ansible.com'
  ).replace(/\/$/, '');

  return [
    {
      id: 'certified',
      contentRepo: 'rh-certified',
      base: hubBase,
      kind: 'hub',
      token: hubToken || null,
    },
    {
      id: 'validated',
      contentRepo: 'validated',
      base: hubBase,
      kind: 'hub',
      token: hubToken || null,
    },
    {
      id: 'galaxy',
      contentRepo: 'published',
      base: galaxyBase,
      kind: 'galaxy',
      token: null,
    },
  ];
}

/** PAH repo names the mock advertises for pulp validation / portal_hub bootstrap. */
export function getPahRepositoryNames(env = process.env) {
  const raw = (env.AAP_MOCK_PAH_REPOS || 'published,validated,rh-certified')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);
  return raw.length ? raw : ['published'];
}
