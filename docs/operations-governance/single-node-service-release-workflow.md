# Single-Node Service Release Workflow

Workflow file:

- `.github/workflows/single_node_service_release.yml`

This workflow is triggered manually with `workflow_dispatch` and runs four stages:

1. Build and push the image to `ghcr.io`
2. Update the release DNS record
3. Run `ansible-playbook -D -C`
4. Optionally run `ansible-playbook -D`

## workflow_dispatch Inputs

In the GitHub Actions UI, choose **Single-Node Service Release** and fill in:

- `service`
  - One of: `accounts`, `accounts-preview`, `rag-server`, `x-cloud-flow`, `x-ops-agent`, `x-scope-hub`
- `service_ref`
  - Branch, tag, or commit SHA of the service repository
- `run_apply`
  - `false`: stop after stage 3
  - `true`: continue to stage 4

CLI example:

```bash
gh workflow run single_node_service_release.yml \
  -f service=rag-server \
  -f service_ref=main \
  -f run_apply=false
```

## Secrets Model

Sensitive values go to GitHub Secrets.
Non-sensitive values stay in repository defaults, workflow env, or the checked-in example vars files.

Important constraint:

- The workflow injects these runtime values itself:
  - `service_compose_image`
  - `service_compose_registry_server`
  - `service_compose_registry_username`
  - `service_compose_registry_password`
  - `service_compose_deploy_targets`
- Therefore each `*_ANSIBLE_VARS_YAML` secret should contain only service secrets and secret-bearing env/config.
- Do not put image names or deploy target metadata into the secret YAML.

## Required GitHub Secrets

### 1. `GHCR_USERNAME`

Template:

```text
your-github-user-or-bot
```

### 2. `GHCR_TOKEN`

Template:

```text
ghp_xxxxxxxxxxxxxxxxxxxx
```

Recommended scopes:

- `write:packages`
- `read:packages`
- `repo` or fine-grained repo read if the same token is also used to read private service repositories

### 3. `CLOUDFLARE_DNS_API_TOKEN`

Template:

```text
cloudflare_dns_token_here
```

Required permission shape:

- Zone read
- DNS edit

### 4. `WORKSPACE_REPO_TOKEN`

Template:

```text
ghp_xxxxxxxxxxxxxxxxxxxx
```

Use this when the control repo `GITHUB_TOKEN` cannot checkout sibling private service repositories.

### 5. `ACCOUNTS_ANSIBLE_VARS_YAML`

Template:

```yaml
service_compose_env_common:
  INTERNAL_SERVICE_TOKEN: CHANGE_ME
  DB_TLS_HOST: postgresql-aws.svc.plus
  DB_TLS_PORT: "5443"
  DB_USER: postgres
  DB_NAME: account
  DB_PASSWORD: CHANGE_ME
  SMTP_HOST: smtp.qq.com
  SMTP_PORT: "587"
  SMTP_FROM: XControl Account <noreply@svc.plus>
  SMTP_USERNAME: CHANGE_ME
  SMTP_PASSWORD: CHANGE_ME
```

### 6. `RAG_SERVER_ANSIBLE_VARS_YAML`

Template:

```yaml
service_compose_env_common:
  DB_TLS_HOST: postgresql-aws.svc.plus
  DB_TLS_PORT: "5443"
  DB_USER: postgres
  DB_NAME: knowledge_db
  DB_PASSWORD: CHANGE_ME
  NVIDIA_API_KEY: CHANGE_ME
  CHUTES_API_URL: https://api.chutes.ai/v1
  CHUTES_API_MODEL: CHANGE_ME
```

### 7. `X_CLOUD_FLOW_ANSIBLE_VARS_YAML`

Template:

```yaml
service_compose_env_common:
  DATABASE_URL: CHANGE_ME
  OPENCLAW_AGENT_ID: x-automation-agent
  OPENCLAW_GATEWAY_URL: CHANGE_ME
  OPENCLAW_GATEWAY_TOKEN: CHANGE_ME
  OPENAI_BASE_URL: CHANGE_ME
  OPENAI_API_KEY: CHANGE_ME
```

### 8. `X_OPS_AGENT_ANSIBLE_VARS_YAML`

Template:

```yaml
service_compose_env_common:
  DATABASE_URL: CHANGE_ME
  OPENCLAW_GATEWAY_URL: CHANGE_ME
  OPENCLAW_GATEWAY_TOKEN: CHANGE_ME
  OPENCLAW_AGENT_ID: xops-agent
  OPENCLAW_AGENT_NAME: XOpsAgent
  AI_GATEWAY_URL: CHANGE_ME
  AI_GATEWAY_API_KEY: CHANGE_ME
  OPENCLAW_REGISTER_ON_START: "true"
```

### 9. `X_SCOPE_HUB_ANSIBLE_VARS_YAML`

Template:

```yaml
service_compose_env_common:
  XSCOPE_MCP_SERVER_AUTH_TOKEN: CHANGE_ME
  XSCOPE_OBSERVE_GATEWAY_URL: CHANGE_ME
  XSCOPE_LLM_OPS_AGENT_URL: CHANGE_ME
  XSCOPE_DEFAULT_TENANT: CHANGE_ME
  XSCOPE_DEFAULT_USER: CHANGE_ME
  XSCOPE_MCP_UPSTREAM_TIMEOUT: 20s
```

## Operational Notes

- `accounts` and `accounts-preview` share the same repository and the same secret payload shape.
- `x-scope-hub` currently assumes the `mcp-server` image is the public release unit.
- The workflow stops after stage 3 unless `run_apply=true`.
- Stable entry domain switching remains manual after stage 4.
