# Single-Node Vault

This deployment keeps Vault as a host process and lets Caddy terminate TLS
for `vault.svc.plus`, proxying to `127.0.0.1:8200`.

## Topology

- `vault server` listens on `127.0.0.1:8200`
- Raft data is stored under `/opt/vault/data`
- Caddy serves `https://vault.svc.plus`

## Lifecycle

Use this deployment in three stages:

1. Deploy Vault as a host process and put Caddy in front of it for public TLS.
2. Initialize and unseal the node once, then store the root token offline.
3. Optionally configure daily admin access with `userpass + TOTP Login MFA`.

## Config files

- Vault config template: `deploy/vault/vault.hcl.example`
- Host config path: `/etc/vault.d/vault.hcl`
- Local secret file: repository root `.env`
  - `VAULT_SERVER_ROOT_ACCESS_TOKEN=<initial-root-token>`
  - optional follow-up admin login values can be added locally after MFA
    bootstrap
- Caddy site block:

```caddy
vault.svc.plus {
  encode zstd gzip
  reverse_proxy 127.0.0.1:8200
  header {
    X-Content-Type-Options "nosniff"
    X-Frame-Options "DENY"
    Referrer-Policy "no-referrer"
  }
}
```

Use `tls internal` only before public DNS is pointed at the host. Once
`vault.svc.plus` resolves to the target host, remove `tls internal` and let
Caddy obtain a public certificate.

## Current instance

The current `vault.svc.plus` instance is already initialized and unsealed. Do
not run `vault operator init` again unless you intentionally wipe the Raft
storage directory and rebuild the node.

For emergency root access only:

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-deploy-example
set -a
source .env
set +a

export VAULT_ADDR=https://vault.svc.plus
vault login "$VAULT_SERVER_ROOT_ACCESS_TOKEN"
vault status
```

Daily admin access is an optional follow-up hardening step. If you want
`userpass + TOTP Login MFA`, use the repository guide
`docs/vault-mfa-setup.md` after the root-only bootstrap is complete.

## Bootstrap from zero

Run the initialization commands on the server itself and target
`127.0.0.1:8200`, because TLS is terminated by Caddy and Vault listens on plain
HTTP locally:

```bash
export VAULT_ADDR=http://127.0.0.1:8200

vault operator init \
  -address="$VAULT_ADDR" \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > /root/vault-init.json

chmod 600 /root/vault-init.json

vault operator unseal \
  -address="$VAULT_ADDR" \
  "$(jq -r '.unseal_keys_b64[0]' /root/vault-init.json)"

jq -r '.root_token' /root/vault-init.json > /root/.vault-token
chmod 600 /root/.vault-token
```

Store the init output in a root-only file or secret manager. Do not commit it.

Expected server-side artifacts after the first bootstrap:

- `/root/vault-init.json`
- `/root/.vault-token`

## Local root token

After `vault operator init`, append the initial root token to the repository
root `.env` file, which is already ignored by Git:

```bash
VAULT_SERVER_ROOT_ACCESS_TOKEN=<initial-root-token>
```

That value can then be used locally for CLI checks:

```bash
export VAULT_ADDR=https://vault.svc.plus
export VAULT_TOKEN="$VAULT_SERVER_ROOT_ACCESS_TOKEN"
vault status
```

## Best practices

- Keep the root token offline and use it only for initialization, recovery, and
  emergency administration.
- Use a named admin account for daily UI access and protect it with
  `userpass + TOTP Login MFA`.
- Do not treat the root token as the normal dashboard login path.
- Keep enrollment QR codes, `otpauth://` URIs, and bootstrap admin passwords
  out of Git and out of long-lived shared documents.
- Revoke temporary bootstrap tokens after the first admin entity has been
  enrolled in MFA.
- Keep Raft snapshots encrypted and off-host.

## Reinitialize

`vault operator init` can only run once for a given Raft data directory. To
reinitialize the node, stop Vault, remove `/opt/vault/data`, start Vault again,
and then rerun the bootstrap steps above.

## Backup

This deployment uses integrated storage (`storage "raft"`), so the supported
backup workflow is a Raft snapshot.

Manual backup example:

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-deploy-example
set -a
source .env
set +a

export VAULT_ADDR=https://vault.svc.plus
export VAULT_TOKEN="$VAULT_SERVER_ROOT_ACCESS_TOKEN"

mkdir -p /tmp/vault-backups
SNAPSHOT="/tmp/vault-backups/vault-$(date +%F-%H%M%S).snap"

vault operator raft snapshot save "$SNAPSHOT"
sha256sum "$SNAPSHOT" > "${SNAPSHOT}.sha256"
```

Recommended practice:

- Copy the snapshot and checksum off-host immediately after creation.
- Keep snapshot files in encrypted storage outside the Vault node itself.
- Test restore in an isolated environment before relying on a backup.
- For large snapshots, set `VAULT_CLIENT_TIMEOUT` to a higher value before save
  or restore.

Vault Enterprise also supports automated snapshots, but this single-node guide
assumes Vault OSS and therefore documents the manual snapshot flow only.

## Restore and host migration

The cleanest host migration path for this single-node deployment is:

1. Take a Raft snapshot on the current node.
2. Copy the snapshot file to the new node.
3. Install Vault and Caddy on the new node with the same topology.
4. Initialize the new node once to create fresh local storage and a temporary
   root token.
5. Force-restore the copied snapshot.
6. Unseal using the original cluster's unseal key, not the temporary key from
   the new node.
7. Repoint DNS or cut traffic over to the new host.

Example recovery on the target host:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_CLIENT_TIMEOUT=10m

# Fresh node bootstrap first.
vault operator init \
  -address="$VAULT_ADDR" \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > /root/vault-init.json

chmod 600 /root/vault-init.json

vault operator unseal \
  -address="$VAULT_ADDR" \
  "$(jq -r '.unseal_keys_b64[0]' /root/vault-init.json)"

export VAULT_TOKEN="$(jq -r '.root_token' /root/vault-init.json)"

# Copy an existing snapshot onto the new host first, for example /root/backup.snap.
vault operator raft snapshot restore -force /root/backup.snap

# After restore, unseal with the original cluster's unseal key.
vault operator unseal -address="$VAULT_ADDR"
```

Important migration notes:

- Restore testing should happen in an isolated network environment first.
- `snapshot restore -force` is required when the snapshot comes from a different
  cluster instance.
- After force restore, the cluster state comes from the snapshot. Keep the
  original unseal key material available.
- If you are replacing the current host in place, stop Vault on the old node
  before final cutover to avoid split-brain or stale operator actions.

## Multi-tenancy

For Vault OSS, the recommended multi-tenant pattern is policy and path
isolation, not namespaces. Vault supports multiple auth methods at the same
time, and policies are path-based, so each tenant can have a dedicated auth
mount, policy set, and secret path prefix.

Recommended OSS pattern:

- One auth method path per tenant or workload class, such as
  `auth/oidc-team-a` or `auth/approle-team-a`
- One KV mount per tenant when stronger operational separation is needed, or
  one shared KV mount with tenant-specific prefixes
- One policy per tenant role, bound only to that tenant's paths
- No shared root token for tenant access

Example KV v2 policy for tenant `team-a` on a shared `secret/` mount:

```hcl
path "secret/data/team-a/*" {
  capabilities = ["create", "update", "patch", "read", "delete"]
}

path "secret/metadata/team-a/*" {
  capabilities = ["list"]
}
```

If you need hard administrative isolation where each tenant has its own auth
methods, policies, and mounts inside a distinct administrative boundary, that is
the Vault Enterprise namespaces feature and is not available in Vault OSS.

## References

- [HashiCorp: Save a Vault snapshot](https://developer.hashicorp.com/vault/docs/sysadmin/snapshots/save)
- [HashiCorp: Restore a Vault snapshot](https://developer.hashicorp.com/vault/docs/sysadmin/snapshots/restore)
- [HashiCorp: Authentication](https://developer.hashicorp.com/vault/docs/auth)
- [HashiCorp: Tokens](https://developer.hashicorp.com/vault/docs/concepts/tokens)
- [HashiCorp: Policies](https://developer.hashicorp.com/vault/docs/concepts/policies)
- [HashiCorp: Secure multi-tenancy with namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces)
- Repository guide: [Vault TOTP MFA Setup](../../docs/vault-mfa-setup.md)
