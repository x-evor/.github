# Vault TOTP MFA Setup

This document covers the practical `userpass + TOTP Login MFA` pattern for the
single-node `vault.svc.plus` deployment.

## Scope

- Vault Community supports `Login MFA`
- Vault Enterprise adds `Step-up MFA`
- Vault Community does not provide the Enterprise self-enrollment flow

For this repository, the supported pattern is administrator-managed TOTP
enrollment.

## Best practices

- Keep the root token offline for emergency use only. Do not use it for daily
  UI administration.
- Use a named admin account for daily access and bind it to an explicit
  `vault-admins` policy.
- Make `userpass` visible for unauthenticated UI login only if it is intended
  for human admin access.
- Keep `userpass` for people, not service-to-service traffic.
- Generate the admin enrollment secret once, deliver it out-of-band, and do not
  commit or log it.
- Enable Login MFA enforcement only after the admin account and enrollment
  secret both exist, otherwise the deployment lands in a half-configured state.
- Revoke any temporary bootstrap admin token created during the first enrollment
  flow.

## Recommended command

Create the TOTP method from the Vault host itself, because Vault listens on
`127.0.0.1:8200` and Caddy handles public TLS:

```bash
export VAULT_ADDR="http://127.0.0.1:8200"

vault write identity/mfa/method/totp \
  issuer="Vault" \
  period=30 \
  digits=6 \
  algorithm="SHA1" \
  skew=1 \
  max_validation_attempts=5
```

The response returns a `method_id` UUID. Keep it. The Vault UI `MFA Setup`
screen asks for that exact value.

## Recommended parameters

| Parameter | Recommended value | Purpose |
| --- | --- | --- |
| `issuer` | `Vault` | Label shown in the authenticator app |
| `period` | `30` | Standard 30-second TOTP interval |
| `digits` | `6` | Broadest client compatibility |
| `algorithm` | `SHA1` | Most widely supported TOTP hash |
| `skew` | `1` | Allows one time-step of clock drift |
| `max_validation_attempts` | `5` | Basic brute-force protection |

Practical meaning:

- `skew`: allows small clock drift between Vault and the authenticator device
- `max_validation_attempts`: limits repeated failed code submissions in one
  validation flow

## Why the UI asks for Method ID

When the Vault UI shows `MFA Setup` and asks for `Method ID`, it is not asking
the user to create MFA. It is asking for the UUID of an MFA method that the
administrator already created.

That flow is expected in Vault Community:

1. The administrator creates the TOTP MFA method.
2. The administrator records the returned `method_id`.
3. The administrator generates enrollment material for the user's `entity_id`.
4. The user enters the `method_id` in the UI and completes verification.

So the `Method ID` prompt means Login MFA is available, but enrollment is still
administrator-managed.

## Configuration process

The recommended Community-edition rollout is:

1. Enable `userpass` and create the admin account.
2. Create the `vault-admins` policy.
3. Create the TOTP MFA method and save the returned `method_id`.
4. Bind Login MFA enforcement to the `userpass` accessor or the admin identity
   group.
5. Generate the enrollment QR or `otpauth://` URI for the administrator's
   `entity_id`.
6. Give the administrator the `method_id` and the one-time enrollment material.
7. Complete the `MFA Setup` page in the Vault UI.

## End-to-end example

Run the bootstrap from the Vault host:

```bash
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="$(cat /root/.vault-token)"

vault auth enable userpass
vault auth tune -listing-visibility=unauth userpass/

cat > /tmp/vault-admins.hcl <<'POL'
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
}
POL

vault policy write vault-admins /tmp/vault-admins.hcl

vault write auth/userpass/users/admin \
  password='<set-strong-password>' \
  token_policies='vault-admins'
```

Create the TOTP method and record the returned UUID:

```bash
vault write identity/mfa/method/totp \
  issuer="Vault" \
  period=30 \
  digits=6 \
  algorithm="SHA1" \
  skew=1 \
  max_validation_attempts=5
```

Generate enrollment material for the admin entity before enabling enforcement:

```bash
USERPASS_ACCESSOR=$(vault auth list -format=json | jq -r '."userpass/".accessor')

BOOTSTRAP=$(vault write -format=json auth/userpass/login/admin password='<set-strong-password>')
ENTITY_ID=$(printf '%s' "$BOOTSTRAP" | jq -r '.auth.entity_id')
BOOTSTRAP_TOKEN=$(printf '%s' "$BOOTSTRAP" | jq -r '.auth.client_token')

vault write -format=json identity/mfa/method/totp/admin-generate \
  method_id='<method-id>' \
  entity_id="$ENTITY_ID" > /tmp/vault-admin-totp.json

vault write identity/mfa/login-enforcement/admin-userpass \
  mfa_method_ids='<method-id>' \
  auth_method_accessors="$USERPASS_ACCESSOR"

vault token revoke "$BOOTSTRAP_TOKEN"
```

What `/tmp/vault-admin-totp.json` contains:

- a base64-encoded QR image in `data.barcode`
- an `otpauth://` URI in `data.url`

Deliver either one to the admin out-of-band, then complete the UI setup page.

## Scripted bootstrap

The repository also includes a helper script for this exact flow:

```bash
scripts/init_vault_admin.sh \
  --password '<set-strong-password>' \
  --root-token "$VAULT_SERVER_ROOT_ACCESS_TOKEN"
```

Useful optional flags:

- `--username <name>` to override the default `admin`
- `--vault-addr http://127.0.0.1:8200` to run directly against the local Vault
  listener
- `--output-dir /tmp` to choose where the enrollment JSON and QR PNG are
  written

If `--root-token` is omitted, the script also accepts `VAULT_TOKEN` or
`VAULT_SERVER_ROOT_ACCESS_TOKEN` from the environment.

The script writes:

- `vault-<username>-totp.json`
- `vault-<username>-totp.png`
- `vault-<username>-totp-uri.txt`

Both files contain sensitive enrollment material and should be handled as
one-time secrets.

## Verification

Check the configuration in this order:

1. `vault auth list` shows `userpass/`
2. `vault read auth/userpass/users/admin` shows `vault-admins` in
   `token_policies`
3. `vault list identity/mfa/method/totp` shows the expected `method_id`
4. `vault read identity/mfa/login-enforcement/admin-userpass` shows the
   `userpass` accessor and the TOTP `method_id`
5. `vault write auth/userpass/login/admin password='...'` returns an
   `mfa_request_id`
6. Vault UI login with `userpass` prompts for `TOTP passcode`, not `Method ID`

## Troubleshooting

If the UI shows `permission denied` after entering a valid `Method ID`, the
deployment is usually only half-configured. The common causes are:

- the TOTP method exists, but no Login MFA enforcement is bound to the target
  `userpass` accessor or identity scope
- the administrator created the TOTP method, but did not generate enrollment
  material for the target `entity_id`
- the admin account exists, but does not have the intended admin policy and is
  therefore not following the expected bootstrap flow

For `vault.svc.plus`, a working Community rollout needs all of these pieces at
the same time:

- a visible `userpass` auth method for UI login
- a `vault-admins` policy
- an admin user bound to that policy
- a TOTP `method_id`
- a Login MFA enforcement referencing the `userpass` accessor
- a generated enrollment secret for the admin `entity_id`

## Deployment defaults

- Daily UI access should use a named admin account, not the root token
- The root token should remain offline for emergency use only
- `userpass` should be reserved for human admin access
- Service-to-service access should use dedicated auth methods, not shared human
  credentials
- The UI should normally prompt for `TOTP passcode`. Seeing `Method ID` again
  after rollout usually means the admin entity was not enrolled correctly

## References

- [HashiCorp: Set up login MFA](https://developer.hashicorp.com/vault/docs/auth/login-mfa)
- [HashiCorp: Login MFA FAQ](https://developer.hashicorp.com/vault/docs/auth/login-mfa/faq)
- [HashiCorp: TOTP MFA API](https://developer.hashicorp.com/vault/api-docs/secret/identity/mfa/totp)
- [HashiCorp: Tokens](https://developer.hashicorp.com/vault/docs/concepts/tokens)
- [HashiCorp: Userpass auth method](https://developer.hashicorp.com/vault/docs/auth/userpass)
