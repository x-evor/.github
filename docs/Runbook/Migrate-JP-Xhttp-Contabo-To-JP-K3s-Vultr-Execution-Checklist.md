# Execution Checklist: JP-XHTTP Contabo -> JP-K3S Vultr

**Purpose**: field execution checklist for the migration from `root@jp-xhttp-contabo.svc.plus` to `root@jp-k3s-vultr.svc.plus`  
**Reference runbook**: [Migrate-JP-Xhttp-Contabo-To-JP-K3s-Vultr.md](/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/docs/Runbook/Migrate-JP-Xhttp-Contabo-To-JP-K3s-Vultr.md)

## Header

| Field | Value |
| --- | --- |
| Source host | `root@jp-xhttp-contabo.svc.plus` |
| Target host | `root@jp-k3s-vultr.svc.plus` |
| Deployment mode | `k3s_platform` |
| Flux auth mode | `public` / blank, `https-basic`, `https-bearer`, or `ssh` |
| Vault mode | `init` / `migrate` |
| Goal | minimal downtime, not zero downtime |
| Source host rule | do not mutate source before DNS cutover |
| Operator | `TBD` |
| Window | `TBD` |

## Command Entry Points

- `playbooks/k3s_platform_bootstrap_with_gitops.yml`
- `playbooks/roles/vhosts/k3s_platform_bootstrap/defaults/main.yml`
- `docs/Runbook/Migrate-JP-Xhttp-Contabo-To-JP-K3s-Vultr.md`

**Bootstrap stage inputs**

- Stage 1: SSH access and host targeting
- `SINGLE_NODE_VPS_SSH_PRIVATE_KEY`
- `SINGLE_NODE_VPS_SSH_HOST`
- `SINGLE_NODE_VPS_SSH_USER`
- `SINGLE_NODE_VPS_SSH_PORT`
- Stage 2: external Vault bootstrap
- `VAULT_URL`
- `VAULT_TOKEN`
- `VAULT_NAMESPACE` (optional)
- Stage 3: FluxCD bootstrap
- `GITOPS_REPO`
- `GITOPS_AUTH_MODE`
- `GITOPS_FLUX_HTTP_USERNAME`
- `GITOPS_FLUX_HTTP_PASSWORD` or `GITOPS_FLUX_TOKEN`
- `GITOPS_FLUX_BEARER_TOKEN`
- `GITOPS_FLUX_DEPLOY_KEY` and `GITOPS_FLUX_DEPLOY_KEY_PUB` for SSH mode

## Batch 0: Preflight

**Goal**

- confirm source and target reachability
- capture current source state
- confirm target capacity and cutover prerequisites

**Commands / entrypoints**

```bash
ssh root@jp-xhttp-contabo.svc.plus 'hostname && docker ps -a && ss -ltnp'
ssh root@jp-xhttp-contabo.svc.plus 'docker exec postgresql-svc-plus psql -U postgres -d postgres -Atc "select datname from pg_database where datistemplate=false order by datname;"'
ssh root@jp-k3s-vultr.svc.plus 'hostname && df -h && free -h && ss -ltnp'
dig +short vault.svc.plus
dig +short console.svc.plus
```

**Pass conditions**

- both hosts are reachable
- source services and DB are readable
- target has enough disk and memory for `k3s + Vault + DB`
- DNS TTL and current records are known

**Stop / rollback trigger**

- SSH unstable on either host
- target capacity is not sufficient
- source DB state cannot be inspected

**Operator log**

| Field | Value |
| --- | --- |
| Time | `TBD` |
| Result | `TBD` |
| Note | `TBD` |

## Batch 1: Target Bootstrap

**Goal**

- bootstrap `jp-k3s-vultr.svc.plus` in `k3s_platform` mode
- verify `k3s`, `helm`, and `flux-system`

**Commands / entrypoints**

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/playbooks
ANSIBLE_CONFIG=../github-org-cloud-neutral-toolkit/ansible/ansible.cfg \
ansible-playbook -i inventory.ini k3s_platform_bootstrap_with_gitops.yml \
  -l jp-k3s-vultr.svc.plus \
  -D
```

```bash
ssh root@jp-k3s-vultr.svc.plus 'systemctl status k3s --no-pager'
ssh root@jp-k3s-vultr.svc.plus 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get ns && kubectl -n flux-system get pods'
```

**Pass conditions**

- `k3s` service is active
- `helm` and `flux` are installed
- `flux-system` exists and controllers are ready

**Stop / rollback trigger**

- `k3s` service does not stay up
- cluster API is not reachable
- `flux-system` controllers are not ready

**Operator log**

| Field | Value |
| --- | --- |
| Time | `TBD` |
| Result | `TBD` |
| Note | `TBD` |

## Batch 2: Vault

**Goal**

- complete Vault bootstrap using `init` or `migrate`
- verify `initialized`, `sealed`, and root login path

**Commands / entrypoints**

For `init`:

```bash
export K3S_PLATFORM_VAULT_BOOTSTRAP_MODE=init
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/playbooks
ANSIBLE_CONFIG=../github-org-cloud-neutral-toolkit/ansible/ansible.cfg \
ansible-playbook -i inventory.ini k3s_platform_bootstrap_with_gitops.yml \
  -l jp-k3s-vultr.svc.plus \
  -D
```

For `migrate`:

```bash
export K3S_PLATFORM_VAULT_BOOTSTRAP_MODE=migrate
export VAULT_ROOT_TOKEN='...'
export VAULT_INIT_JSON='...'
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/playbooks
ANSIBLE_CONFIG=../github-org-cloud-neutral-toolkit/ansible/ansible.cfg \
ansible-playbook -i inventory.ini k3s_platform_bootstrap_with_gitops.yml \
  -l jp-k3s-vultr.svc.plus \
  -D
```

```bash
ssh root@jp-k3s-vultr.svc.plus 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl -n extsvc get pods,svc'
ssh root@jp-k3s-vultr.svc.plus 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl -n extsvc exec statefulset/vault -- /bin/vault status'
```

**Pass conditions**

- Vault pod is ready
- `vault status` shows `Initialized true`
- `vault status` shows `Sealed false`
- root login path is available

**Stop / rollback trigger**

- Vault remains uninitialized in `migrate`
- Vault remains sealed after `init`
- root login path cannot be validated

**Operator log**

| Field | Value |
| --- | --- |
| Time | `TBD` |
| Result | `TBD` |
| Note | `TBD` |

## Batch 3: GitOps

**Goal**

- reconcile root source
- sync all platform pods
- verify critical namespaces are ready

**Commands / entrypoints**

```bash
ssh root@jp-k3s-vultr.svc.plus 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && flux reconcile source git platform-config -n flux-system --timeout=5m'
ssh root@jp-k3s-vultr.svc.plus 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && flux reconcile kustomization platform-root -n flux-system --with-source --timeout=10m'
ssh root@jp-k3s-vultr.svc.plus 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get gitrepositories,kustomizations,helmreleases -A'
ssh root@jp-k3s-vultr.svc.plus 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get pods -A'
```

**Pass conditions**

- root Flux source reconciles cleanly
- all expected namespaces exist
- platform pods are ready or have understood transient restarts only

**Stop / rollback trigger**

- repeated Flux reconcile failures
- namespace creation stalls
- critical system pods fail to become ready

**Operator log**

| Field | Value |
| --- | --- |
| Time | `TBD` |
| Result | `TBD` |
| Note | `TBD` |

## Batch 4: DB Migrate

**Goal**

- perform initial full sync
- validate target DB stack
- perform final short freeze and cut over

**Execution order**

1. `stunnel-client`
2. `stunnel-server`
3. `postgresql-svc-plus`

**Important**

- the service order above is the migration tracking order
- actual traffic cutover must happen only after target DB validation is complete
- keep the source host unchanged until final DB cutover and DNS switch

**Commands / entrypoints**

Initial sync and validation:

```bash
ssh root@jp-xhttp-contabo.svc.plus 'docker exec postgresql-svc-plus pg_dump -U postgres -d account -Fc > /root/account.dump'
ssh root@jp-xhttp-contabo.svc.plus 'docker exec postgresql-svc-plus pg_dump -U postgres -d knowledge_db -Fc > /root/knowledge_db.dump'
scp root@jp-xhttp-contabo.svc.plus:/root/account.dump /tmp/account.dump
scp root@jp-xhttp-contabo.svc.plus:/root/knowledge_db.dump /tmp/knowledge_db.dump
scp /tmp/account.dump root@jp-k3s-vultr.svc.plus:/root/account.dump
scp /tmp/knowledge_db.dump root@jp-k3s-vultr.svc.plus:/root/knowledge_db.dump
ssh root@jp-k3s-vultr.svc.plus 'docker exec -i postgresql-svc-plus pg_restore -U postgres -d account /root/account.dump'
ssh root@jp-k3s-vultr.svc.plus 'docker exec -i postgresql-svc-plus pg_restore -U postgres -d knowledge_db /root/knowledge_db.dump'
```

Target-side validation:

```bash
ssh root@jp-k3s-vultr.svc.plus 'docker exec postgresql-svc-plus psql -U postgres -d postgres -Atc "select datname, pg_database_size(datname) from pg_database where datistemplate=false order by datname;"'
ssh root@jp-k3s-vultr.svc.plus 'docker exec postgresql-svc-plus psql -U postgres -d account -Atc "select count(*) from users;"'
ssh root@jp-k3s-vultr.svc.plus 'docker exec postgresql-svc-plus psql -U postgres -d knowledge_db -Atc "select count(*) from documents;"'
```

Final short freeze and final sync:

```bash
# freeze writes at the application layer first
# then repeat the final dump / restore or delta sync
```

**Pass conditions**

- target DB restores cleanly
- key table counts and schema checks match expectations
- target `stunnel-client` and `stunnel-server` are reachable
- application smoke tests can use the target DB path

**Stop / rollback trigger**

- restore errors on target
- row counts drift unexpectedly
- target DB tunnel path is not stable
- app smoke fails against target DB

**Operator log**

| Field | Value |
| --- | --- |
| Time | `TBD` |
| Result | `TBD` |
| Note | `TBD` |

## Batch 5: DNS Cutover

**Goal**

- switch public traffic after platform, Vault, and DB are ready
- confirm public health and basic smoke

**Commands / entrypoints**

```bash
dig +short console.svc.plus
dig +short vault.svc.plus
# apply DNS record updates through the normal Cloudflare change path
curl -skf https://console.svc.plus/healthz
curl -skf https://vault.svc.plus/v1/sys/health
```

**Pass conditions**

- public DNS resolves to the target host
- public smoke checks succeed
- no immediate 5xx spike or auth failure appears

**Stop / rollback trigger**

- DNS resolves incorrectly after update window
- public health checks fail
- platform or Vault auth breaks after cutover

**Operator log**

| Field | Value |
| --- | --- |
| Time | `TBD` |
| Result | `TBD` |
| Note | `TBD` |

## Batch 6: Observation / Rollback Window

**Goal**

- keep the source as rollback anchor
- monitor the target until the window closes

**Monitor**

- `5xx` or ingress failure
- Vault auth failure
- DB connection failure
- Flux reconcile failure
- stale DNS cache behavior

**Rollback trigger**

- sustained customer-visible error
- persistent Vault failure
- persistent DB inconsistency
- unrecoverable GitOps drift on target

**Rollback order**

1. point DNS back to `jp-xhttp-contabo.svc.plus`
2. stop new writes on the target if needed
3. revert DB consumers to the source path
4. preserve target Vault artifacts for review

**Operator log**

| Field | Value |
| --- | --- |
| Time | `TBD` |
| Result | `TBD` |
| Note | `TBD` |
