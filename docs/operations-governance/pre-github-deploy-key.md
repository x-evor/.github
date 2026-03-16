# Pre GitHub Deploy Key

This document standardizes the SSH key used by `Service Release Control Plane` for Ansible CD stages.

## Goal

Prepare a dedicated GitHub Actions deploy key for the single-node release workflow.

Do not reuse a personal daily-use SSH key when a dedicated CI key can be used instead.

## Public Vs Private Key Cheat Sheet

| Location | Expected value | Use `.pub`? | Example |
| --- | --- | --- | --- |
| GitHub Organization Secret `SINGLE_NODE_VPS_SSH_PRIVATE_KEY` | private key contents | No | `<BEGIN_OPENSSH_PRIVATE_KEY> ...` |
| GitHub repository `Deploy keys` page | public key contents | Yes | `ssh-ed25519 AAAA... github-actions@cloud-neutral-toolkit` |
| GitHub personal `SSH keys` page | public key contents | Yes | `ssh-ed25519 AAAA... github-actions@cloud-neutral-toolkit` |
| Deploy host `~/.ssh/authorized_keys` | public key contents | Yes | `ssh-ed25519 AAAA... github-actions@cloud-neutral-toolkit` |
| Local SSH test with `ssh -i` | private key file | No | `~/.ssh/id_ed25519_us_xhttp_ci` |

Quick rule:

- anything ending with `.pub` is public-key material
- GitHub Actions secret `SINGLE_NODE_VPS_SSH_PRIVATE_KEY` must never use `.pub`
- `Deploy keys`, `SSH keys`, and `authorized_keys` must never use the private key

## Required Secret

Configure this GitHub Organization Secret:

- `SINGLE_NODE_VPS_SSH_PRIVATE_KEY`

This secret must contain the full private key contents, not a filesystem path.

Supported payload shapes:

1. Raw multi-line private key
2. One-line private key with escaped `\n`
3. Base64-encoded full private key

Do not store:

- `~/.ssh/id_rsa`
- `/path/to/id_ed25519`
- `*.pub` public key contents
- quoted JSON wrappers

## Recommended Key Shape

Use a dedicated keypair without passphrase for CI only.

Recommended local filename:

- `~/.ssh/id_ed25519_us_xhttp_ci`

## Create The Keypair

```bash
ssh-keygen -t ed25519 \
  -C "github-actions@cloud-neutral-toolkit" \
  -f ~/.ssh/id_ed25519_us_xhttp_ci \
  -N ""
```

## Install The Public Key On The Deploy Host

```bash
ssh root@5.78.45.49 'install -d -m 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
cat ~/.ssh/id_ed25519_us_xhttp_ci.pub | \
  ssh root@5.78.45.49 'cat >> ~/.ssh/authorized_keys'
```

## Verify The Key Locally

```bash
ssh-keygen -y -f ~/.ssh/id_ed25519_us_xhttp_ci >/dev/null && echo ok
ssh -i ~/.ssh/id_ed25519_us_xhttp_ci root@5.78.45.49 'hostname'
```

Expected result:

- `ssh-keygen` succeeds without asking for a passphrase
- direct SSH to `root@5.78.45.49` succeeds

## Write The Secret With GitHub CLI

Refresh local auth first if needed:

```bash
gh auth refresh -h github.com -s admin:org
```

Then write the organization secret for the `.github` repo:

```bash
gh secret set \
  --org cloud-neutral-toolkit \
  --repos .github \
  SINGLE_NODE_VPS_SSH_PRIVATE_KEY < ~/.ssh/id_ed25519_us_xhttp_ci
```

## Common Failure Modes

If workflow logs still show:

```text
Invalid SINGLE_NODE_VPS_SSH_PRIVATE_KEY payload
```

check these first:

1. The secret contains the private key contents, not the file path
2. The secret is not a `.pub` public key
3. The key is not encrypted with a passphrase
4. The org secret is visible to `cloud-neutral-toolkit/.github`
5. The deploy host still has the matching public key in `authorized_keys`

## Rotation

When rotating the deploy key:

1. create a new dedicated keypair
2. append the new public key to the deploy host
3. overwrite `SINGLE_NODE_VPS_SSH_PRIVATE_KEY`
4. verify a dry-run release
5. remove the old public key from the deploy host
