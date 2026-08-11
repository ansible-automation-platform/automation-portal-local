/**
 * Console Hub auth: ansible-galaxy style offline/refresh token → access token.
 *
 * AAP_MOCK_HUB_TOKEN is typically the offline token from console.redhat.com
 * (same value as ansible.cfg galaxy_server.token with auth_url). Hub APIs
 * expect Authorization: Bearer <access_token>, not the offline token itself.
 */

export const DEFAULT_HUB_AUTH_URL =
  'https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token';

export const DEFAULT_HUB_AUTH_CLIENT_ID = 'cloud-services';

/**
 * @param {object} opts
 * @param {string} [opts.refreshToken]
 * @param {string} [opts.authUrl]
 * @param {string} [opts.clientId]
 * @param {typeof fetch} [opts.fetchImpl]
 * @param {() => number} [opts.now]
 * @param {{ warn?: Function, info?: Function }} [opts.log]
 * @param {number} [opts.skewMs] refresh this many ms before expiry
 */
export function createHubAccessTokenProvider(opts = {}) {
  const refreshToken = (opts.refreshToken || '').trim();
  const authUrl = (opts.authUrl || DEFAULT_HUB_AUTH_URL).trim();
  const clientId = (opts.clientId || DEFAULT_HUB_AUTH_CLIENT_ID).trim();
  const fetchImpl = opts.fetchImpl || fetch;
  const now = opts.now || (() => Date.now());
  const skewMs = opts.skewMs ?? 60_000;
  const log = opts.log;

  let accessToken = null;
  let expiresAtMs = 0;
  let inflight = null;

  async function exchange() {
    const res = await fetchImpl(authUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        client_id: clientId,
        refresh_token: refreshToken,
      }),
    });
    const text = await res.text();
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      body = null;
    }
    if (!res.ok || !body?.access_token) {
      const detail =
        body?.error_description ||
        body?.error ||
        text.slice(0, 180) ||
        `HTTP ${res.status}`;
      throw new Error(detail);
    }
    return body;
  }

  async function getAccessToken() {
    if (!refreshToken) return null;
    if (accessToken && now() < expiresAtMs - skewMs) {
      return accessToken;
    }
    if (!inflight) {
      inflight = (async () => {
        try {
          const body = await exchange();
          accessToken = body.access_token;
          const ttlSec = Number(body.expires_in) || 900;
          expiresAtMs = now() + ttlSec * 1000;
          log?.info?.(
            `aap-mock hub: SSO access token refreshed (expires_in=${ttlSec}s)`,
          );
          return accessToken;
        } catch (err) {
          accessToken = null;
          expiresAtMs = 0;
          log?.warn?.(
            `aap-mock hub: SSO token exchange failed: ${err.message}`,
          );
          return null;
        } finally {
          inflight = null;
        }
      })();
    }
    return inflight;
  }

  /**
   * Headers for console Hub. Prefer Bearer access token from SSO exchange;
   * fall back to classic `Token <raw>` for non-offline API tokens.
   */
  async function getAuthHeaders() {
    if (!refreshToken) return {};
    const access = await getAccessToken();
    if (access) {
      return { Authorization: `Bearer ${access}` };
    }
    return { Authorization: `Token ${refreshToken}` };
  }

  return {
    hasRefreshToken: Boolean(refreshToken),
    getAccessToken,
    getAuthHeaders,
    /** test helper */
    _cacheState: () => ({ accessToken, expiresAtMs }),
  };
}

/** Attach shared SSO auth to Hub remotes (mutates list). */
export function attachHubAuth(remotes, tokenProvider) {
  if (!tokenProvider?.hasRefreshToken) return remotes;
  for (const remote of remotes) {
    if (remote.kind === 'hub') {
      remote.getAuthHeaders = () => tokenProvider.getAuthHeaders();
    }
  }
  return remotes;
}
