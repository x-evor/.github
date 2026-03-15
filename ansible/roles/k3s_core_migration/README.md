# k3s_core_migration

Reusable Ansible role for the single-node `K3s + APISIX + ExternalDNS + cert-manager + shared stunnel-client + core apps` migration flow.

This role is intentionally shaped so it can be copied into:

- `/Users/shenlan/workspaces/cloud-neutral-toolkit/playbooks/roles/`

and then included from a playbook with:

```yaml
- include_role:
    name: k3s_core_migration
```

From this control repo, run it with:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/deploy_k3s_core_migration.yml
```

## What it does

1. Creates required namespaces.
2. Renders manifests into a local workspace.
3. Runs `kubectl diff` preview:
   - ExternalDNS provider secret
   - shared `stunnel-client`
   - stable / preview app manifests
4. Applies manifests only when not in check mode.
5. Verifies:
   - K8s pods are ready
   - optional preview endpoint returns a non-5xx response
   - optional stable endpoint returns a non-5xx response

## Why this role works better with `-C -D`

The role is split into four explicit stages:

1. `render`
2. `diff`
3. `apply`
4. `verify`

That means:

- `ansible-playbook -C -D` renders everything and runs diff preview without mutating the cluster
- `apply` and `verify` are skipped automatically in check mode
- you can also force render-only mode with `k3s_core_render_only=true`

## Expected variables

- `k3s_core_root_domain`
- `k3s_core_cluster_issuer`
- `k3s_core_dns_secret`
- `k3s_core_services`

See `defaults/main.yml` for the full schema.
