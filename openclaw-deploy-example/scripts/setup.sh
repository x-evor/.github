#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<'EOF'
OpenClaw one-shot setup script (VPS / Cloud Run / macOS local)

Usage:
  setup.sh [version] [domain] [options]

Examples:
  # Use defaults (version=latest, domain=openclaw-vps.svc.plus), VPS dry-run
  curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/setup.sh \
    | bash -s -- --dry-run

  # Use options style
  curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/setup.sh \
    | bash -s -- --version latest --domain openclaw-vps.svc.plus --dry-run

  # Legacy positional compatibility
  curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/setup.sh \
    | bash -s -- 17 openclaw-vps.svc.plus --dry-run

  # VPS (default mode) dry-run
  curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/setup.sh \
    | bash -s -- --domain openclaw-vps.svc.plus --dry-run

  # VPS apply
  curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/setup.sh \
    | bash -s -- --domain openclaw-vps.svc.plus --mode vps \
      --meta-url "postgres://openclaw@127.0.0.1:5432/openclawfs?sslmode=disable" \
      --meta-password "<pg-password>" \
      --gateway-token "<token>" --zai-api-key "<key>"

  # Cloud Run apply
  curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/setup.sh \
    | bash -s -- --domain openclaw-cloud-run.svc.plus --mode cloud-run \
      --project xzerolab-480008 --region asia-northeast1

  # macOS local apply
  curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/setup.sh \
    | bash -s -- --mode macos-local --domain openclaw-local.svc.plus \
      --state-dir "$HOME/.openclaw/local-state" --config-path "$HOME/.openclaw/openclaw-local.json"

Options:
  -v, --version <value>                  Version argument (default: latest)
  -d, --domain <name>                    Public domain (mode default: vps=openclaw-vps.svc.plus, cloud-run=openclaw-cloud-run.svc.plus, macos-local=openclaw-local.svc.plus)
  --mode <vps|single-host|cloud-run|macos-local>
                                          Deploy mode (default: vps)
  --dry-run                              Print actions only

  --bucket <name>                        JuiceFS object storage bucket on GCS (default: openclawbot-data)
  --meta-url <url>                       JuiceFS metadata URL, typically PostgreSQL (required for vps/single-host)
  --meta-password <value>                Optional JuiceFS META_PASSWORD written to env file
  --juicefs-name <name>                  JuiceFS filesystem name used on first format (default: openclawfs)
  --juicefs-cache-dir <path>             JuiceFS local cache dir (single-host default: /var/cache/juicefs/openclaw)
  --juicefs-cache-size <MiB>             JuiceFS cache size in MiB (default: 1024)
  --gcs-credentials <path>               GOOGLE_APPLICATION_CREDENTIALS path written to env file
  --state-dir <path>                     State dir mount path (mode default: vps/cloud-run=/data, macos-local=$HOME/.openclaw/local-state)
  --config-path <path>                   Config path (mode default: vps=/data/openclaw-vps.json, cloud-run=/data/openclaw-cloud-run.json, macos-local=$HOME/.openclaw/openclaw-local.json)
  --control-ui-origin <origin>           Allowed origin (single-host default: https://<domain>, cloud-run default: *)
  --env-file <path>                      Env file path (default: /root/.env for vps, ~/.openclaw/.env for macos-local)

  --service <name>                       Service name (default: openclawbot-svc-plus)
  --region <name>                        GCP region (default: asia-northeast1)
  --project <id>                         GCP project id (cloud-run only)
  --service-account <email>              Cloud Run runtime service account
  --cloud-run-image <image>              Cloud Run image (default: ghcr.io/openclaw/openclaw:latest)
  --gateway-token-secret <name>          Secret name for OPENCLAW_GATEWAY_TOKEN (default: internal-service-token)
  --zai-secret <name>                    Secret name for Z_AI_API_KEY / ZAI_API_KEY (default: zai-api-key)

  --gateway-token <token>                Write/replace OPENCLAW_GATEWAY_TOKEN in env file (vps default: /root/.env)
  --zai-api-key <key>                    Write/replace Z_AI_API_KEY in env file (vps default: /root/.env)
  --acme-email <email>                   Optional Caddy ACME email
  --skip-browser                         Skip Google Chrome install/config for vps/single-host mode
  -h, --help                             Show help
EOF
}

log() {
  printf '[setup] %s\n' "$*"
}

warn() {
  printf '[setup][warn] %s\n' "$*" >&2
}

die() {
  printf '[setup][error] %s\n' "$*" >&2
  exit 1
}

print_cmd() {
  local out=()
  local arg
  for arg in "$@"; do
    out+=("$(printf '%q' "$arg")")
  done
  printf '  + %s\n' "${out[*]}"
}

run_cmd() {
  print_cmd "$@"
  if ((DRY_RUN)); then
    return 0
  fi
  "$@"
}

run_shell() {
  local cmd="$1"
  printf '  + %s\n' "$cmd"
  if ((DRY_RUN)); then
    return 0
  fi
  bash -lc "$cmd"
}

run_shell_with_env_file() {
  local cmd="$1"
  local quoted_env_file
  quoted_env_file="$(printf '%q' "$ENV_FILE")"
  run_shell "set -a; [ -f ${quoted_env_file} ] && . ${quoted_env_file}; set +a; ${cmd}"
}

write_file() {
  local path="$1"
  local mode="$2"
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  if ((DRY_RUN)); then
    log "[dry-run] write ${path} (mode ${mode})"
    sed 's/^/    /' "$tmp"
    rm -f "$tmp"
    return 0
  fi
  install -d "$(dirname "$path")"
  install -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: ${cmd}"
}

APT_UPDATED=0
ensure_apt_packages() {
  command -v apt-get >/dev/null 2>&1 || die "apt-get not found. Single-host mode currently supports Debian/Ubuntu only."
  if ((APT_UPDATED == 0)); then
    run_cmd apt-get update
    APT_UPDATED=1
  fi
  run_cmd apt-get install -y "$@"
}

ensure_juicefs() {
  if command -v juicefs >/dev/null 2>&1; then
    log "juicefs already installed"
    return 0
  fi
  log "installing juicefs"
  ensure_apt_packages ca-certificates curl
  run_shell 'curl -sSL https://d.juicefs.com/install | bash -s -- /usr/local/bin'
}

ensure_caddy() {
  if command -v caddy >/dev/null 2>&1; then
    log "caddy already installed"
    return 0
  fi
  log "installing caddy"
  ensure_apt_packages caddy
}

ensure_google_chrome() {
  if ((INSTALL_BROWSER == 0)); then
    log "skip browser install by request"
    return 0
  fi
  if command -v google-chrome >/dev/null 2>&1; then
    log "google-chrome already installed"
    return 0
  fi
  log "installing google-chrome"
  ensure_apt_packages ca-certificates curl fonts-liberation xdg-utils fonts-noto-cjk
  run_cmd curl -fsSL -o /tmp/google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  run_cmd apt-get install -y /tmp/google-chrome-stable_current_amd64.deb
  run_cmd rm -f /tmp/google-chrome-stable_current_amd64.deb
}

ensure_openclaw() {
  if command -v openclaw >/dev/null 2>&1; then
    log "openclaw already installed"
    return 0
  fi
  log "installing openclaw"
  if [[ "$OPENCLAW_VERSION" == "latest" ]]; then
    run_shell 'curl -fsSL https://openclaw.ai/install.sh | bash'
    return 0
  fi
  if [[ "$OPENCLAW_VERSION" =~ ^20[0-9]{2}\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]] && command -v npm >/dev/null 2>&1; then
    run_cmd npm install -g "openclaw@${OPENCLAW_VERSION}"
    return 0
  fi
  warn "version=${OPENCLAW_VERSION} cannot be pinned automatically in single-host mode; installing latest"
  run_shell 'curl -fsSL https://openclaw.ai/install.sh | bash'
}

upsert_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"

  if [[ -z "$value" ]]; then
    return 0
  fi

  if ((DRY_RUN)); then
    log "[dry-run] set ${key}=<redacted> in ${file}"
    return 0
  fi

  touch "$file"
  chmod 600 "$file"
  if [[ "${EUID}" -eq 0 ]]; then
    chown root:root "$file"
  fi

  if grep -q "^${key}=" "$file"; then
    local escaped="$value"
    escaped="${escaped//\\/\\\\}"
    escaped="${escaped//&/\\&}"
    escaped="${escaped//|/\\|}"
    sed -i "s|^${key}=.*|${key}=${escaped}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

ensure_single_host_config_json() {
  run_cmd mkdir -p "$(dirname "$CONFIG_PATH")"
  if [[ ! -f "$CONFIG_PATH" ]]; then
    write_file "$CONFIG_PATH" "0644" <<EOF
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token"
    },
    "controlUi": {
      "allowedOrigins": [
        "${CONTROL_UI_ORIGIN}"
      ]
    }
  },
  "browser": {
    "defaultProfile": "openclaw",
    "headless": true,
    "noSandbox": true,
    "executablePath": "/usr/bin/google-chrome"
  }
}
EOF
    return 0
  fi

  if ((DRY_RUN)); then
    log "[dry-run] patch ${CONFIG_PATH} for gateway/browser defaults"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg origin "$CONTROL_UI_ORIGIN" '
    .gateway = (.gateway // {}) |
    .gateway.port = 18789 |
    .gateway.mode = "local" |
    .gateway.bind = "lan" |
    .gateway.auth = (.gateway.auth // {}) |
    .gateway.auth.mode = "token" |
    .gateway.controlUi = (.gateway.controlUi // {}) |
    .gateway.controlUi.allowedOrigins = [$origin] |
    .browser = (.browser // {}) |
    .browser.defaultProfile = "openclaw" |
    .browser.headless = true |
    .browser.noSandbox = true |
    .browser.executablePath = "/usr/bin/google-chrome"
  ' "$CONFIG_PATH" >"$tmp"
  install -m 0644 "$tmp" "$CONFIG_PATH"
  rm -f "$tmp"
}

ensure_macos_local_config_json() {
  run_cmd mkdir -p "$(dirname "$CONFIG_PATH")"
  if [[ ! -f "$CONFIG_PATH" ]]; then
    write_file "$CONFIG_PATH" "0644" <<EOF
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token"
    },
    "controlUi": {
      "allowedOrigins": [
        "${CONTROL_UI_ORIGIN}"
      ]
    }
  }
}
EOF
    return 0
  fi

  if ((DRY_RUN)); then
    log "[dry-run] patch ${CONFIG_PATH} for macos-local gateway defaults"
    return 0
  fi

  require_command jq
  local tmp
  tmp="$(mktemp)"
  jq --arg origin "$CONTROL_UI_ORIGIN" '
    .gateway = (.gateway // {}) |
    .gateway.port = 18789 |
    .gateway.mode = "local" |
    .gateway.bind = "lan" |
    .gateway.auth = (.gateway.auth // {}) |
    .gateway.auth.mode = "token" |
    .gateway.controlUi = (.gateway.controlUi // {}) |
    .gateway.controlUi.allowedOrigins = [$origin]
  ' "$CONFIG_PATH" >"$tmp"
  install -m 0644 "$tmp" "$CONFIG_PATH"
  rm -f "$tmp"
}

validate_local_env_file() {
  if ((DRY_RUN)); then
    log "[dry-run] skip strict env validation"
    return 0
  fi
  [[ -f "$ENV_FILE" ]] || die "${ENV_FILE} not found"
  grep -q '^OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE" || die "missing OPENCLAW_GATEWAY_TOKEN in ${ENV_FILE}"
  if ! grep -q '^Z_AI_API_KEY=' "$ENV_FILE" && ! grep -q '^ZAI_API_KEY=' "$ENV_FILE"; then
    die "missing Z_AI_API_KEY (or ZAI_API_KEY) in ${ENV_FILE}"
  fi
}

validate_single_host_env_file() {
  validate_local_env_file
  if ((DRY_RUN)); then
    return 0
  fi
  grep -q '^JUICEFS_META_URL=' "$ENV_FILE" || die "missing JUICEFS_META_URL in ${ENV_FILE}"
}

ensure_single_host_juicefs_volume() {
  if ((DRY_RUN)); then
    run_shell_with_env_file 'juicefs status "$JUICEFS_META_URL" >/dev/null 2>&1 || juicefs format --storage gs --bucket "'"${GCS_BUCKET}"'" "$JUICEFS_META_URL" "'"${JUICEFS_NAME}"'"'
    return 0
  fi

  if run_shell_with_env_file 'juicefs status "$JUICEFS_META_URL" >/dev/null 2>&1'; then
    log "JuiceFS volume already formatted"
    return 0
  fi

  log "formatting JuiceFS volume ${JUICEFS_NAME}"
  run_shell_with_env_file 'juicefs format --storage gs --bucket "'"${GCS_BUCKET}"'" "$JUICEFS_META_URL" "'"${JUICEFS_NAME}"'"'
}

ensure_single_host_files() {
  local juicefs_bin
  juicefs_bin="$(command -v juicefs || true)"
  if [[ -z "$juicefs_bin" ]]; then
    juicefs_bin="/usr/local/bin/juicefs"
  fi
  local juicefs_writeback_flag=""
  if ((JUICEFS_WRITEBACK)); then
    juicefs_writeback_flag="--writeback"
  fi

  write_file "$MOUNT_SERVICE_FILE" "0644" <<EOF
[Unit]
Description=Mount OpenClaw JuiceFS (${JUICEFS_NAME}) to ${STATE_DIR}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${ENV_FILE}
ExecStart=/bin/bash -lc 'exec ${juicefs_bin} mount --cache-dir "\${JUICEFS_CACHE_DIR}" --cache-size "\${JUICEFS_CACHE_SIZE}" ${juicefs_writeback_flag} "\${JUICEFS_META_URL}" "${STATE_DIR}"'
ExecStop=/bin/bash -lc 'exec ${juicefs_bin} umount "${STATE_DIR}" || true'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  local openclaw_bin
  openclaw_bin="$(command -v openclaw || true)"
  if [[ -z "$openclaw_bin" ]]; then
    openclaw_bin="/usr/local/bin/openclaw"
  fi

  write_file "$OPENCLAW_SERVICE_FILE" "0644" <<EOF
[Unit]
Description=OpenClawBot single-host local process service
Requires=openclawbot-data.mount.service
After=openclawbot-data.mount.service network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=10
TimeoutStartSec=0
Environment="OPENCLAW_STATE_DIR=${STATE_DIR}"
Environment="OPENCLAW_CONFIG_PATH=${CONFIG_PATH}"
Environment="OPENCLAW_GATEWAY_CONTROL_UI_ALLOWED_ORIGINS=${CONTROL_UI_ORIGIN}"
EnvironmentFile=${ENV_FILE}
ExecStart=${openclaw_bin} gateway run --bind lan --allow-unconfigured --auth token --port 18789
KillSignal=SIGTERM
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  write_file "$CADDY_DROPIN_FILE" "0644" <<EOF
[Service]
EnvironmentFile=${ENV_FILE}
EOF

  local caddy_email_line=""
  if [[ -n "$ACME_EMAIL" ]]; then
    caddy_email_line="  email ${ACME_EMAIL}"
  fi

  write_file "$CADDYFILE" "0644" <<EOF
{
  acme_ca https://acme-v02.api.letsencrypt.org/directory
${caddy_email_line}
}

${DOMAIN} {
  @maps path *.map
  respond @maps 404

  header {
    -X-Forwarded-For
    -X-Forwarded-Proto
    -X-Forwarded-Host
    -X-Real-IP
  }

  reverse_proxy 127.0.0.1:18789 {
    header_up Authorization "Bearer {\$OPENCLAW_GATEWAY_TOKEN}"
    header_up Host {http.request.host}
    header_up X-Forwarded-Proto {http.request.scheme}
    header_up X-Forwarded-Host {http.request.host}
    flush_interval -1
  }

  header {
    X-Content-Type-Options "nosniff"
    X-Frame-Options "DENY"
    Referrer-Policy "no-referrer"
    Permissions-Policy "camera=(), microphone=(), geolocation=()"
  }

  log {
    output file /var/log/caddy/clawdbot.access.log {
      roll_size 50MiB
      roll_keep 10
      roll_keep_for 720h
    }
  }
}
EOF
}

setup_single_host() {
  [[ "${EUID}" -eq 0 ]] || die "single-host mode must run as root"
  [[ -n "$JUICEFS_META_URL_INPUT" ]] || die "--meta-url is required for vps/single-host mode"
  log "mode=single-host domain=${DOMAIN} bucket=${GCS_BUCKET} state=${STATE_DIR} config=${CONFIG_PATH}"

  ensure_apt_packages ca-certificates curl gnupg lsb-release jq fuse3
  ensure_juicefs
  ensure_caddy
  ensure_google_chrome
  ensure_openclaw

  run_cmd mkdir -p "$STATE_DIR"
  run_cmd mkdir -p "$JUICEFS_CACHE_DIR"

  if ((DRY_RUN)); then
    log "[dry-run] ensure ${ENV_FILE} exists and is mode 600"
  else
    mkdir -p "$(dirname "$ENV_FILE")"
    touch "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    chown root:root "$ENV_FILE"
  fi

  upsert_env_var "$ENV_FILE" "OPENCLAW_GATEWAY_TOKEN" "$OPENCLAW_GATEWAY_TOKEN_INPUT"
  upsert_env_var "$ENV_FILE" "Z_AI_API_KEY" "$ZAI_API_KEY_INPUT"
  upsert_env_var "$ENV_FILE" "JUICEFS_META_URL" "$JUICEFS_META_URL_INPUT"
  upsert_env_var "$ENV_FILE" "META_PASSWORD" "$META_PASSWORD_INPUT"
  upsert_env_var "$ENV_FILE" "GOOGLE_APPLICATION_CREDENTIALS" "$GOOGLE_APPLICATION_CREDENTIALS_INPUT"
  upsert_env_var "$ENV_FILE" "GCS_BUCKET_NAME" "$GCS_BUCKET"
  upsert_env_var "$ENV_FILE" "JUICEFS_NAME" "$JUICEFS_NAME"
  upsert_env_var "$ENV_FILE" "JUICEFS_CACHE_DIR" "$JUICEFS_CACHE_DIR"
  upsert_env_var "$ENV_FILE" "JUICEFS_CACHE_SIZE" "$JUICEFS_CACHE_SIZE"

  ensure_single_host_files
  validate_single_host_env_file
  ensure_single_host_juicefs_volume

  run_cmd systemctl daemon-reload
  run_cmd systemctl enable --now openclawbot-data.mount.service
  run_cmd systemctl restart openclawbot-data.mount.service
  run_cmd mkdir -p "$(dirname "$CONFIG_PATH")"
  run_cmd mkdir -p "${STATE_DIR}/workspace"
  ensure_single_host_config_json
  run_cmd systemctl enable --now openclawbot-svc-plus.service
  run_cmd systemctl restart openclawbot-svc-plus.service
  run_cmd systemctl enable --now caddy.service
  run_cmd systemctl restart caddy.service

  if ((DRY_RUN)); then
    log "single-host dry-run finished"
    return 0
  fi

  log "verification"
  run_cmd systemctl --no-pager --full status openclawbot-data.mount.service
  run_cmd systemctl --no-pager --full status openclawbot-svc-plus.service
  run_cmd systemctl --no-pager --full status caddy.service
  run_shell "mount | grep ' on ${STATE_DIR} ' || true"
  run_shell "ss -ltnp | grep ':18789' || true"
  run_shell "curl -fsSI http://127.0.0.1:18789 >/dev/null && echo 'openclaw local endpoint ok' || true"
  run_shell "curl -fsSI https://${DOMAIN} >/dev/null && echo 'caddy https endpoint ok' || true"
}

setup_macos_local() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macos-local mode must run on macOS"
  log "mode=macos-local domain=${DOMAIN} bucket=${GCS_BUCKET} state=${STATE_DIR} config=${CONFIG_PATH}"

  ensure_openclaw

  run_cmd mkdir -p "$STATE_DIR"
  run_cmd mkdir -p "${STATE_DIR}/workspace"

  if ((DRY_RUN)); then
    log "[dry-run] ensure ${ENV_FILE} exists and is mode 600"
  else
    mkdir -p "$(dirname "$ENV_FILE")"
    touch "$ENV_FILE"
    chmod 600 "$ENV_FILE"
  fi

  upsert_env_var "$ENV_FILE" "OPENCLAW_GATEWAY_TOKEN" "$OPENCLAW_GATEWAY_TOKEN_INPUT"
  upsert_env_var "$ENV_FILE" "Z_AI_API_KEY" "$ZAI_API_KEY_INPUT"
  ensure_macos_local_config_json

  log "macos-local setup finished"
  log "next steps:"
  log "  export OPENCLAW_STATE_DIR=${STATE_DIR}"
  log "  export OPENCLAW_CONFIG_PATH=${CONFIG_PATH}"
  log "  openclaw gateway run --bind lan --allow-unconfigured --auth token --port 18789"
}

resolve_project_id() {
  if [[ -n "$PROJECT_ID" ]]; then
    return 0
  fi
  if command -v gcloud >/dev/null 2>&1; then
    PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
  fi
  [[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || die "--project is required for cloud-run mode"
}

ensure_bucket_exists() {
  if ((DRY_RUN)); then
    run_cmd gsutil ls -b "gs://${GCS_BUCKET}"
    run_cmd gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${GCS_BUCKET}"
    return 0
  fi
  if gsutil ls -b "gs://${GCS_BUCKET}" >/dev/null 2>&1; then
    log "bucket exists: gs://${GCS_BUCKET}"
  else
    run_cmd gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${GCS_BUCKET}"
  fi
}

ensure_service_account_exists() {
  if ((DRY_RUN)); then
    run_cmd gcloud iam service-accounts describe "$SERVICE_ACCOUNT" --project "$PROJECT_ID"
    return 0
  fi

  if gcloud iam service-accounts describe "$SERVICE_ACCOUNT" --project "$PROJECT_ID" >/dev/null 2>&1; then
    log "service account exists: ${SERVICE_ACCOUNT}"
    return 0
  fi

  local suffix="@${PROJECT_ID}.iam.gserviceaccount.com"
  if [[ "$SERVICE_ACCOUNT" != *"$suffix" ]]; then
    die "service account ${SERVICE_ACCOUNT} not found and cannot auto-create outside project ${PROJECT_ID}"
  fi
  local sa_name="${SERVICE_ACCOUNT%$suffix}"
  run_cmd gcloud iam service-accounts create "$sa_name" \
    --display-name "OpenClawBot Service Account" \
    --project "$PROJECT_ID"
}

require_secret_exists() {
  local name="$1"
  if ((DRY_RUN)); then
    run_cmd gcloud secrets describe "$name" --project "$PROJECT_ID"
    return 0
  fi
  gcloud secrets describe "$name" --project "$PROJECT_ID" >/dev/null 2>&1 || die "secret ${name} not found in project ${PROJECT_ID}"
}

grant_cloud_run_iam() {
  run_cmd gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:${SERVICE_ACCOUNT}" \
    --role roles/storage.objectAdmin \
    --condition None \
    --quiet

  run_cmd gcloud secrets add-iam-policy-binding "$GATEWAY_TOKEN_SECRET" \
    --member "serviceAccount:${SERVICE_ACCOUNT}" \
    --role roles/secretmanager.secretAccessor \
    --project "$PROJECT_ID" \
    --quiet

  run_cmd gcloud secrets add-iam-policy-binding "$ZAI_SECRET_NAME" \
    --member "serviceAccount:${SERVICE_ACCOUNT}" \
    --role roles/secretmanager.secretAccessor \
    --project "$PROJECT_ID" \
    --quiet
}

deploy_cloud_run() {
  local env_vars="NODE_ENV=production,OPENCLAW_STATE_DIR=${STATE_DIR},OPENCLAW_CONFIG_PATH=${CONFIG_PATH},OPENCLAW_GATEWAY_MODE=local,OPENCLAW_GATEWAY_CONTROL_UI_ALLOWED_ORIGINS=${CONTROL_UI_ORIGIN}"
  local secret_bindings="OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN_SECRET}:latest,Z_AI_API_KEY=${ZAI_SECRET_NAME}:latest,ZAI_API_KEY=${ZAI_SECRET_NAME}:latest"

  run_cmd gcloud run deploy "$SERVICE_NAME" \
    --image "$CLOUD_RUN_IMAGE" \
    --platform managed \
    --region "$REGION" \
    --project "$PROJECT_ID" \
    --service-account "$SERVICE_ACCOUNT" \
    --execution-environment gen2 \
    --cpu 2 \
    --memory 4Gi \
    --min-instances 0 \
    --max-instances 10 \
    --allow-unauthenticated \
    --port 8080 \
    --set-env-vars "$env_vars" \
    --update-secrets "$secret_bindings" \
    --add-volume "name=gcs-data,type=cloud-storage,bucket=${GCS_BUCKET}" \
    --add-volume-mount "volume=gcs-data,mount-path=${STATE_DIR}" \
    --quiet
}

setup_cloud_run() {
  log "mode=cloud-run service=${SERVICE_NAME} project=${PROJECT_ID:-<auto>} region=${REGION} bucket=${GCS_BUCKET}"
  require_command gcloud
  require_command gsutil

  resolve_project_id
  if [[ -z "$SERVICE_ACCOUNT" ]]; then
    SERVICE_ACCOUNT="openclawbot-sa@${PROJECT_ID}.iam.gserviceaccount.com"
  fi
  if [[ -z "$CONTROL_UI_ORIGIN" ]]; then
    CONTROL_UI_ORIGIN="*"
  fi

  run_cmd gcloud config set project "$PROJECT_ID"
  run_cmd gcloud services enable run.googleapis.com secretmanager.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project "$PROJECT_ID"

  ensure_bucket_exists
  ensure_service_account_exists
  require_secret_exists "$GATEWAY_TOKEN_SECRET"
  require_secret_exists "$ZAI_SECRET_NAME"
  grant_cloud_run_iam
  deploy_cloud_run

  run_cmd gcloud run services describe "$SERVICE_NAME" \
    --region "$REGION" \
    --project "$PROJECT_ID" \
    --format 'value(status.url,status.conditions[0].status,spec.template.spec.serviceAccountName)'
}

MODE="vps"
DRY_RUN=0
OPENCLAW_VERSION="latest"
DOMAIN="openclaw-vps.svc.plus"
GCS_BUCKET="openclawbot-data"
STATE_DIR="/data"
CONFIG_PATH="/data/openclaw-vps.json"
CONTROL_UI_ORIGIN=""
SERVICE_NAME="openclawbot-svc-plus"
REGION="asia-northeast1"
PROJECT_ID="${GCP_PROJECT_ID:-}"
SERVICE_ACCOUNT=""
GATEWAY_TOKEN_SECRET="internal-service-token"
ZAI_SECRET_NAME="zai-api-key"
OPENCLAW_GATEWAY_TOKEN_INPUT=""
ZAI_API_KEY_INPUT=""
JUICEFS_META_URL_INPUT="${JUICEFS_META_URL:-}"
META_PASSWORD_INPUT="${META_PASSWORD:-}"
GOOGLE_APPLICATION_CREDENTIALS_INPUT="${GOOGLE_APPLICATION_CREDENTIALS:-}"
JUICEFS_NAME="${JUICEFS_NAME:-openclawfs}"
JUICEFS_CACHE_DIR="${JUICEFS_CACHE_DIR:-/var/cache/juicefs/openclaw}"
JUICEFS_CACHE_SIZE="${JUICEFS_CACHE_SIZE:-1024}"
JUICEFS_WRITEBACK=1
ACME_EMAIL=""
CLOUD_RUN_IMAGE="ghcr.io/openclaw/openclaw:latest"
CLOUD_RUN_IMAGE_EXPLICIT=0
ENV_FILE="/root/.env"
MOUNT_SERVICE_FILE="/etc/systemd/system/openclawbot-data.mount.service"
OPENCLAW_SERVICE_FILE="/etc/systemd/system/openclawbot-svc-plus.service"
CADDYFILE="/etc/caddy/Caddyfile"
CADDY_DROPIN_FILE="/etc/systemd/system/caddy.service.d/openclaw-env.conf"
INSTALL_BROWSER=1
VERSION_SET_BY_FLAG=0
DOMAIN_SET_EXPLICIT=0
STATE_DIR_SET_BY_FLAG=0
CONFIG_PATH_SET_BY_FLAG=0
ENV_FILE_SET_BY_FLAG=0
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)
      [[ $# -ge 2 ]] || die "--version requires a value"
      OPENCLAW_VERSION="$2"
      VERSION_SET_BY_FLAG=1
      shift 2
      ;;
    -d|--domain)
      [[ $# -ge 2 ]] || die "--domain requires a value"
      DOMAIN="$2"
      DOMAIN_SET_EXPLICIT=1
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || die "--mode requires a value"
      MODE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --bucket)
      [[ $# -ge 2 ]] || die "--bucket requires a value"
      GCS_BUCKET="$2"
      shift 2
      ;;
    --meta-url)
      [[ $# -ge 2 ]] || die "--meta-url requires a value"
      JUICEFS_META_URL_INPUT="$2"
      shift 2
      ;;
    --meta-password)
      [[ $# -ge 2 ]] || die "--meta-password requires a value"
      META_PASSWORD_INPUT="$2"
      shift 2
      ;;
    --juicefs-name)
      [[ $# -ge 2 ]] || die "--juicefs-name requires a value"
      JUICEFS_NAME="$2"
      shift 2
      ;;
    --juicefs-cache-dir)
      [[ $# -ge 2 ]] || die "--juicefs-cache-dir requires a value"
      JUICEFS_CACHE_DIR="$2"
      shift 2
      ;;
    --juicefs-cache-size)
      [[ $# -ge 2 ]] || die "--juicefs-cache-size requires a value"
      JUICEFS_CACHE_SIZE="$2"
      shift 2
      ;;
    --gcs-credentials)
      [[ $# -ge 2 ]] || die "--gcs-credentials requires a value"
      GOOGLE_APPLICATION_CREDENTIALS_INPUT="$2"
      shift 2
      ;;
    --state-dir)
      [[ $# -ge 2 ]] || die "--state-dir requires a value"
      STATE_DIR="$2"
      STATE_DIR_SET_BY_FLAG=1
      shift 2
      ;;
    --config-path)
      [[ $# -ge 2 ]] || die "--config-path requires a value"
      CONFIG_PATH="$2"
      CONFIG_PATH_SET_BY_FLAG=1
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || die "--env-file requires a value"
      ENV_FILE="$2"
      ENV_FILE_SET_BY_FLAG=1
      shift 2
      ;;
    --control-ui-origin)
      [[ $# -ge 2 ]] || die "--control-ui-origin requires a value"
      CONTROL_UI_ORIGIN="$2"
      shift 2
      ;;
    --service)
      [[ $# -ge 2 ]] || die "--service requires a value"
      SERVICE_NAME="$2"
      shift 2
      ;;
    --region)
      [[ $# -ge 2 ]] || die "--region requires a value"
      REGION="$2"
      shift 2
      ;;
    --project)
      [[ $# -ge 2 ]] || die "--project requires a value"
      PROJECT_ID="$2"
      shift 2
      ;;
    --service-account)
      [[ $# -ge 2 ]] || die "--service-account requires a value"
      SERVICE_ACCOUNT="$2"
      shift 2
      ;;
    --gateway-token-secret)
      [[ $# -ge 2 ]] || die "--gateway-token-secret requires a value"
      GATEWAY_TOKEN_SECRET="$2"
      shift 2
      ;;
    --zai-secret)
      [[ $# -ge 2 ]] || die "--zai-secret requires a value"
      ZAI_SECRET_NAME="$2"
      shift 2
      ;;
    --gateway-token)
      [[ $# -ge 2 ]] || die "--gateway-token requires a value"
      OPENCLAW_GATEWAY_TOKEN_INPUT="$2"
      shift 2
      ;;
    --zai-api-key)
      [[ $# -ge 2 ]] || die "--zai-api-key requires a value"
      ZAI_API_KEY_INPUT="$2"
      shift 2
      ;;
    --acme-email)
      [[ $# -ge 2 ]] || die "--acme-email requires a value"
      ACME_EMAIL="$2"
      shift 2
      ;;
    --cloud-run-image)
      [[ $# -ge 2 ]] || die "--cloud-run-image requires a value"
      CLOUD_RUN_IMAGE="$2"
      CLOUD_RUN_IMAGE_EXPLICIT=1
      shift 2
      ;;
    --skip-browser)
      INSTALL_BROWSER=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL_ARGS[@]} -gt 2 ]]; then
  die "too many positional arguments: ${POSITIONAL_ARGS[*]}"
fi

if [[ ${#POSITIONAL_ARGS[@]} -ge 1 ]]; then
  if ((VERSION_SET_BY_FLAG == 0)); then
    OPENCLAW_VERSION="${POSITIONAL_ARGS[0]}"
  elif ((DOMAIN_SET_EXPLICIT == 0)); then
    DOMAIN="${POSITIONAL_ARGS[0]}"
    DOMAIN_SET_EXPLICIT=1
  fi
fi
if [[ ${#POSITIONAL_ARGS[@]} -eq 2 ]]; then
  if ((DOMAIN_SET_EXPLICIT == 0)); then
    DOMAIN="${POSITIONAL_ARGS[1]}"
    DOMAIN_SET_EXPLICIT=1
  fi
fi

apply_mode_defaults() {
  case "$MODE" in
    vps|single-host)
      MODE="single-host"
      if ((DOMAIN_SET_EXPLICIT == 0)); then
        DOMAIN="openclaw-vps.svc.plus"
      fi
      if ((STATE_DIR_SET_BY_FLAG == 0)); then
        STATE_DIR="/data"
      fi
      if ((CONFIG_PATH_SET_BY_FLAG == 0)); then
        CONFIG_PATH="/data/openclaw-vps.json"
      fi
      if ((ENV_FILE_SET_BY_FLAG == 0)); then
        ENV_FILE="/root/.env"
      fi
      ;;
    cloud-run)
      if ((DOMAIN_SET_EXPLICIT == 0)); then
        DOMAIN="openclaw-cloud-run.svc.plus"
      fi
      if ((STATE_DIR_SET_BY_FLAG == 0)); then
        STATE_DIR="/data"
      fi
      if ((CONFIG_PATH_SET_BY_FLAG == 0)); then
        CONFIG_PATH="/data/openclaw-cloud-run.json"
      fi
      ;;
    macos-local)
      if ((DOMAIN_SET_EXPLICIT == 0)); then
        DOMAIN="openclaw-local.svc.plus"
      fi
      if ((STATE_DIR_SET_BY_FLAG == 0)); then
        STATE_DIR="${HOME}/.openclaw/local-state"
      fi
      if ((CONFIG_PATH_SET_BY_FLAG == 0)); then
        CONFIG_PATH="${HOME}/.openclaw/openclaw-local.json"
      fi
      if ((ENV_FILE_SET_BY_FLAG == 0)); then
        ENV_FILE="${HOME}/.openclaw/.env"
      fi
      ;;
    *)
      die "unsupported mode: ${MODE}. expected vps|single-host|cloud-run|macos-local"
      ;;
  esac
}

apply_mode_defaults

if [[ -z "$CONTROL_UI_ORIGIN" ]]; then
  if [[ "$MODE" == "cloud-run" ]]; then
    CONTROL_UI_ORIGIN="*"
  else
    CONTROL_UI_ORIGIN="https://${DOMAIN}"
  fi
fi

if ((CLOUD_RUN_IMAGE_EXPLICIT == 0)) && [[ "$OPENCLAW_VERSION" != "latest" ]]; then
  if [[ "$OPENCLAW_VERSION" =~ ^20[0-9]{2}\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]]; then
    CLOUD_RUN_IMAGE="ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}"
  else
    warn "version=${OPENCLAW_VERSION} is not a recognized OpenClaw tag; cloud-run image remains ${CLOUD_RUN_IMAGE}"
  fi
fi

log "version=${OPENCLAW_VERSION}"
log "mode=${MODE}"
log "domain=${DOMAIN}"
log "dry_run=${DRY_RUN}"

case "$MODE" in
  single-host)
    setup_single_host
    ;;
  cloud-run)
    setup_cloud_run
    ;;
  macos-local)
    setup_macos_local
    ;;
  *)
    die "unsupported mode after normalization: ${MODE}"
    ;;
esac

log "done"
