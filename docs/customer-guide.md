# Customer Guide

Deploy the Ansible Automation Portal for EAP testing with your own AAP controller.

## Prerequisites

- **Podman** 4.x+ with `podman compose` (or Docker 28.1.0+ with Compose)
- **8 GB RAM** minimum
- An AAP controller with OAuth configured

## Quick Start

```bash
# 1. Untar the archive
tar xzf automation-portal-local-*.tar.gz && cd automation-portal-local

# 2. Configure
cp .env.example .env
```

Edit `.env` with your AAP details:

```bash
AAP_MOCK=0
APME_EXTERNAL=1
AAP_HOST_URL=https://your-aap-controller.example.com
AAP_PUBLIC_URL=https://your-aap-controller.example.com
AAP_TOKEN=<your-aap-token>
OAUTH_CLIENT_ID=<your-oauth-client-id>
OAUTH_CLIENT_SECRET=<your-oauth-client-secret>
NODE_TLS_REJECT_UNAUTHORIZED=0    # dev only — for self-signed AAP certs
```

```bash
# 3. Start
make start SKIP_BUILD=1
```

Portal UI: http://localhost:7007

Login with **Sign in with Ansible Automation Platform** using your AAP credentials.

## Multi-org Configuration

Multi-org syncs organizations, users, teams, and job templates from your AAP controller. The `orgs` list is pre-configured in the tarball. To change which organizations are synced, edit `rhdh-local/configs/app-config/app-config.portal.yaml`:

```yaml
catalog:
  providers:
    rhaap:
      development:
        multiOrgEnabled: true
        orgs:
          - Default
          - Engineering
```

Restart after editing: `make stop && make start SKIP_BUILD=1`

## Updating Plugins

When you receive an updated set of plugin `.tgz` files:

```bash
# 1. Copy new tarballs (replace existing ones)
cp new-plugins/*.tgz local-plugins/portal/

# 2. Restart
make stop && make start SKIP_BUILD=1
```

## Running on AWS EC2

1. Launch an EC2 instance (RHEL 9 or Fedora recommended, t3.xlarge or larger)
2. Install Podman: `sudo dnf install -y podman podman-compose`
3. Upload the tarball: `scp automation-portal-local-*.tar.gz ec2-user@<ip>:~`
4. SSH in and follow the [Quick Start](#quick-start) steps
5. Access the portal at `http://<ec2-public-ip>:7007`

Ensure port 7007 is open in the EC2 security group.

## Stopping and Cleanup

```bash
make stop          # Stop services (data preserved)
make start SKIP_BUILD=1   # Restart with existing data

make clean         # Full cleanup — removes all data and volumes
```

## Troubleshooting

**OAuth login fails with "Auth provider misconfigured"**
- Verify `AAP_PUBLIC_URL` is set in `.env` and matches the URL reachable from your browser
- Ensure the OAuth application on AAP has redirect URI: `http://localhost:7007/api/auth/rhaap/handler/frame`

**Portal starts but no templates or users appear**
- Check logs: `make logs` — look for AAP connection errors
- Verify `AAP_HOST_URL` and `AAP_TOKEN` are correct
- Ensure `NODE_TLS_REJECT_UNAUTHORIZED=0` is set if AAP uses self-signed certs

**Port 7007 already in use**
- Stop any existing portal: `make stop`
- Or check: `podman ps` and `podman stop <container>`
