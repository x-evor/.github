# Cloud Run 环境变量配置

## Gateway 认证 Token（推荐：使用 Secret Manager）

### 生产环境配置（Secret Manager）

Cloud Run 服务使用 Google Cloud Secret Manager 安全存储认证 token：

```yaml
# service.yaml 配置
env:
  - name: OPENCLAW_GATEWAY_TOKEN
    valueFrom:
      secretKeyRef:
        name: internal-service-token
        key: latest
```

**Secret 信息：**

- **Secret 名称**: `internal-service-token`
- **Secret 值**: `uTvryFvAbz6M5sRtmTaSTQY6otLZ95hneBsWqXu+35I=`
- **共享服务**:
  - `openclawbot.svc.plus` (本服务)
  - `console.svc.plus`
  - `accounts.svc.plus`

### 开发/测试环境配置（环境变量）

如果不使用 Secret Manager，可以直接设置环境变量：

```bash
export OPENCLAW_GATEWAY_TOKEN=uTvryFvAbz6M5sRtmTaSTQY6otLZ95hneBsWqXu+35I=
```

## Token 格式

- **编码**: Base64
- **长度**: 44 字符
- **生成方式**: `openssl rand -base64 32`

## 与其他服务的 Token 对比

### accounts.svc.plus

```bash
INTERNAL_SERVICE_TOKEN=uTvryFvAbz6M5sRtmTaSTQY6otLZ95hneBsWqXu+35I=
```

### openclawbot (本地配置)

```bash
gateway.auth.token=<openclaw-gateway-token>
```

### openclawbot (Cloud Run)

```bash
OPENCLAW_GATEWAY_TOKEN=mNrXA9Lm+5cs6wMziYMafJgkjTJg45OMiB1YTXEt5E8=
```

## 安全注意事项

⚠️ **重要**:

- 此 token 仅用于 Cloud Run 部署
- 不要将 token 提交到公开仓库
- 生产环境应使用 Secret Manager 存储敏感信息

## 使用 Secret Manager（推荐）

在生产环境中，建议使用 Google Cloud Secret Manager：

```bash
# 创建 secret
echo -n "mNrXA9Lm+5cs6wMziYMafJgkjTJg45OMiB1YTXEt5E8=" | \
  gcloud secrets create openclaw-gateway-token \
  --data-file=- \
  --project=xzerolab-480008

# 授予服务账号访问权限
gcloud secrets add-iam-policy-binding openclaw-gateway-token \
  --member="serviceAccount:openclawbot-sa@xzerolab-480008.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project=xzerolab-480008

# 在 Cloud Run 中使用 secret
gcloud run services update openclawbot-svc-plus \
  --update-secrets=OPENCLAW_GATEWAY_TOKEN=openclaw-gateway-token:latest \
  --region=asia-northeast1 \
  --project=xzerolab-480008
```

## 更新 Token

如需更换 token：

1. 生成新 token:

   ```bash
   openssl rand -base64 32
   ```

2. 更新配置文件:
   - `deploy/gcp/cloud-run/service.yaml`
   - `deploy/gcp/cloud-run/deploy.sh`

3. 重新部署服务
