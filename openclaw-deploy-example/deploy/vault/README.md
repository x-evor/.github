# Vault Migration Runbook

This deployment keeps Vault behind Caddy for `vault.svc.plus` and documents
the supported raft-join migration path from the current source node to a new
target node.

## Topology

- `vault server` listens on `127.0.0.1:8200`
- Raft data is stored under `/opt/vault/data`
- Caddy serves `https://vault.svc.plus`

## Lifecycle

Use this deployment in three stages:

1. Expose the current leader's raft listener temporarily so a second node can
   join.
2. Start a new Vault node with `retry_join`, let raft data replicate, then
   unseal the new node with the original cluster unseal material.
3. Cut traffic to the new node and then restore the source node's raft bind
   address back to loopback.

## Config files

- Vault config template: `deploy/vault/vault.hcl.example`
- Caddy site template: `deploy/vault/vault.svc.plus.caddy`
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

The Ansible Vault role writes the same block to
`/etc/caddy/conf.d/vault.svc.plus.caddy` and imports it from the main
`/etc/caddy/Caddyfile`.

Use `tls internal` only before public DNS is pointed at the host. Once
`vault.svc.plus` resolves to the target host, remove `tls internal` and let
Caddy obtain a public certificate.

## Current instance

The current `vault.svc.plus` instance is already initialized and unsealed. Do
not run `vault operator init` again unless you intentionally wipe the Raft
storage directory and rebuild the node.

Current migration constraint on the source host:

- Raft cluster traffic was originally bound to `127.0.0.1:8201`, so a new host
  could not join the existing node as a live raft peer.
- The source host can be switched temporarily to `0.0.0.0:8201` so the target
  node can join, replicate, and then be cut over.
- If the original unseal material is missing, the join can still be prepared
  but the new node cannot be fully activated until those keys are recovered.

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

## Raft Join Migration

This is the preferred host migration path when the source node is still
healthy:

1. Temporarily change the source node's raft bind address to `0.0.0.0:8201`.
2. Keep `api_addr` pointed at the public Vault hostname so clients continue to
   use Caddy.
3. Start the new node with `retry_join { leader_api_addr = "https://vault.svc.plus" }`
   and publish its own raft port on `0.0.0.0:8201`.
4. Let raft synchronize and confirm the new node appears in
   `vault operator raft list-peers`.
5. Unseal the new node with the original cluster unseal material.
6. Switch DNS or reverse-proxy traffic to the new host.
7. Revert the source node's raft bind address back to loopback and keep it as
   a standby until the migration is fully validated.

Example target-node bootstrap:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_CLIENT_TIMEOUT=10m

# Start the node with retry_join enabled, then wait for it to appear in the
# raft peer list.
vault operator raft list-peers

# If the node is still sealed, unseal it using the original cluster key
# material. Do not re-init the new node if the goal is to join the existing
# cluster.
vault operator unseal -address="$VAULT_ADDR"
```

Important migration notes:

- Restore testing should happen in an isolated network environment first.
- Keep the original unseal key material available before starting the join.
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
