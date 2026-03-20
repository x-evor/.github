# Cloud Run 部署修复总结

## 问题诊断

### 原始错误

```
Gateway auth is set to token, but no token is configured.
Set gateway.auth.token (or OPENCLAW_GATEWAY_TOKEN), or pass --token.
```

### 根本原因

虽然在 `service.yaml` 中配置了 `OPENCLAW_GATEWAY_TOKEN` 环境变量，但应用代码在读取 token 时没有检查这个环境变量名称。应用期望的是 `INTERNAL_SERVICE_TOKEN`（与 console.svc.plus 和 accounts.svc.plus 共享的 token 名称）。

## 解决方案

### 1. 代码修改

#### `src/gateway/auth.ts` (第 192-197 行)

```typescript
const token =
  authConfig.token ??
  env.OPENCLAW_GATEWAY_TOKEN ??
  env.INTERNAL_SERVICE_TOKEN ?? // 新增：支持 INTERNAL_SERVICE_TOKEN
  env.CLAWDBOT_GATEWAY_TOKEN ??
  undefined;
```

**作用**: 添加 `INTERNAL_SERVICE_TOKEN` 作为 token 来源的备选项，确保与其他服务的命名一致性。

#### `src/cli/gateway-cli/run.ts` (第 224 行)

```typescript
"Set gateway.auth.token (or OPENCLAW_GATEWAY_TOKEN/INTERNAL_SERVICE_TOKEN), or pass --token.",
```

**作用**: 更新错误提示信息，告知用户可以使用 `INTERNAL_SERVICE_TOKEN`。

### 2. 部署配置修改

#### `deploy/gcp/cloud-run/service.yaml`

```yaml
env:
  - name: NODE_ENV
    value: production
  - name: OPENCLAW_STATE_DIR
    value: /data
  - name: OPENCLAW_CONFIG_PATH # 新增：方便配置同步
    value: /data/openclaw.json
  - name: OPENCLAW_GATEWAY_MODE
    value: local
  - name: OPENCLAW_GATEWAY_TOKEN
    valueFrom:
      secretKeyRef:
        name: internal-service-token
        key: latest
```

**作用**: 注入 `OPENCLAW_GATEWAY_TOKEN` (映射 `internal-service-token` Secret)，不需要额外注入 `INTERNAL_SERVICE_TOKEN` (代码优先使用 `OPENCLAW_GATEWAY_TOKEN`)。同时显式指定配置文件路径在 GCS 挂载点，确保配置持久化。

### 3. 构建与持续交互 (Cloud Build)

#### `cloudbuild.yaml`

```yaml
steps:
  # ... 构建和推送 ...
  - name: "gcr.io/google.com/cloudsdktool/cloud-sdk:slim"
    args:
      - "run"
      - "deploy"
      - "openclawbot-svc-plus"
      - "--service-account=openclawbot-sa@$PROJECT_ID.iam.gserviceaccount.com"
      - "--set-env-vars=NODE_ENV=production,OPENCLAW_STATE_DIR=/data,OPENCLAW_CONFIG_PATH=/data/openclaw.json,OPENCLAW_GATEWAY_MODE=local"
      - "--update-secrets=OPENCLAW_GATEWAY_TOKEN=internal-service-token:latest"
      - "--add-volume=name=gcs-data,type=cloud-storage,bucket=openclawbot-data"
      - "--add-volume-mount=volume=gcs-data,mount-path=/data"
      - "--execution-environment=gen2"
```

**作用**: 实现自动化部署，集成 Secret Manager 和 GCS 存储卷。

### 4. 存储与权限

- **GCS Bucket**: `openclawbot-data` (挂载至 `/data`)
- **Secret Manager**: `internal-service-token`
- **服务账号**: `openclawbot-sa@xzerolab-480008.iam.gserviceaccount.com`

## 提交历史

```
73e53c62b - feat: support INTERNAL_SERVICE_TOKEN for gateway auth consistency
4af0f8665 - fix: explicit gateway mode and allow-unconfigured flag to ensure startup
2b0c7aefa - fix: add wait time for service account propagation
ba7b0be2a - docs: add Secret Manager quick reference guide
ae3f10732 - feat: use Secret Manager for shared INTERNAL_SERVICE_TOKEN
14750de9d - fix: copy entire ui directory instead of just dist
```

## 部署验证

### 检查构建状态

```bash
gcloud builds list --project=xzerolab-480008 --limit=3
```

### 检查服务状态

```bash
gcloud run services describe openclawbot-svc-plus \
  --region=asia-northeast1 \
  --project=xzerolab-480008
```

### 检查日志

```bash
gcloud run services logs read openclawbot-svc-plus \
  --region=asia-northeast1 \
  --project=xzerolab-480008 \
  --limit=50
```

### 使用验证脚本

```bash
cd deploy/gcp/cloud-run
./verify-deployment.sh
```

## 预期结果

部署成功后，应该看到：

1. ✅ Cloud Run 服务状态为 `Ready: True`
2. ✅ 容器成功启动并监听端口 8080
3. ✅ 日志中没有 "Gateway auth is set to token, but no token is configured" 错误
4. ✅ 环境变量 `OPENCLAW_GATEWAY_TOKEN` 已正确注入 (且应用能通过它完成认证)
5. ✅ 服务可以通过 Cloud Run URL 访问

## 故障排查

如果部署仍然失败，检查：

1. **Secret Manager 权限**

   ```bash
   gcloud secrets get-iam-policy internal-service-token --project=xzerolab-480008
   ```

   确保服务账号 `openclawbot-sa@xzerolab-480008.iam.gserviceaccount.com` 有 `roles/secretmanager.secretAccessor` 权限。

2. **Secret 值**

   ```bash
   gcloud secrets versions access latest --secret=internal-service-token --project=xzerolab-480008
   ```

   确认值为: `uTvryFvAbz6M5sRtmTaSTQY6otLZ95hneBsWqXu+35I=`

3. **环境变量注入**

   ```bash
   gcloud run services describe openclawbot-svc-plus \
     --region=asia-northeast1 \
     --project=xzerolab-480008 \
     --format="yaml(spec.template.spec.containers[0].env)"
   ```

4. **容器日志**
   查看详细的启动日志，确认 token 是否被正确读取。

## 后续优化建议

1. **统一环境变量命名**: 考虑在所有服务中统一使用 `INTERNAL_SERVICE_TOKEN`
2. **Token 轮换**: 建议每 90 天更换一次 token
3. **监控和告警**: 配置 Cloud Monitoring 监控服务健康状态
4. **自动化测试**: 添加部署后的自动化健康检查
