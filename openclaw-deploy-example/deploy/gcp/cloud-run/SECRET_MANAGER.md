# Secret Manager 快速参考

## 共享 Token 配置

### Token 信息

- **Secret 名称**: `internal-service-token`
- **Secret 值**: `uTvryFvAbz6M5sRtmTaSTQY6otLZ95hneBsWqXu+35I=`
- **格式**: Base64 编码（44 字符）
- **用途**: 服务间认证

### 共享服务

1. **openclawbot.svc.plus** (本服务)
   - 环境变量: `OPENCLAW_GATEWAY_TOKEN`
   - 用途: Gateway 认证

2. **console.svc.plus**
   - 环境变量: `INTERNAL_SERVICE_TOKEN`
   - 用途: 内部服务调用认证

3. **accounts.svc.plus**
   - 环境变量: `INTERNAL_SERVICE_TOKEN`
   - 用途: 内部服务调用认证

## 快速命令

### 创建 Secret

```bash
echo -n "uTvryFvAbz6M5sRtmTaSTQY6otLZ95hneBsWqXu+35I=" | \
  gcloud secrets create internal-service-token \
    --data-file=- \
    --project=xzerolab-480008 \
    --replication-policy="automatic"
```

### 查看 Secret

```bash
gcloud secrets describe internal-service-token \
  --project=xzerolab-480008
```

### 读取 Secret 值

```bash
gcloud secrets versions access latest \
  --secret=internal-service-token \
  --project=xzerolab-480008
```

### 授予服务账号访问权限

```bash
gcloud secrets add-iam-policy-binding internal-service-token \
  --member="serviceAccount:openclawbot-sa@xzerolab-480008.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project=xzerolab-480008
```

### 更新 Secret 值

```bash
echo -n "NEW_TOKEN_VALUE" | \
  gcloud secrets versions add internal-service-token \
    --data-file=- \
    --project=xzerolab-480008
```

## Cloud Run 配置

### 在 service.yaml 中使用

```yaml
env:
  - name: OPENCLAW_GATEWAY_TOKEN
    valueFrom:
      secretKeyRef:
        name: internal-service-token
        key: latest
```

### 在 gcloud 命令中使用

```bash
gcloud run deploy openclawbot-svc-plus \
  --update-secrets OPENCLAW_GATEWAY_TOKEN=internal-service-token:latest \
  --region asia-northeast1 \
  --project xzerolab-480008
```

## 安全最佳实践

1. ✅ **使用 Secret Manager** 而不是环境变量
2. ✅ **最小权限原则** - 只授予必要的访问权限
3. ✅ **定期轮换** - 建议每 90 天更换一次 token
4. ✅ **审计日志** - 启用 Secret Manager 审计日志
5. ✅ **版本管理** - 使用 `latest` 或特定版本号

## Token 轮换流程

1. 生成新 token:

   ```bash
   openssl rand -base64 32
   ```

2. 添加新版本到 Secret Manager:

   ```bash
   echo -n "NEW_TOKEN" | \
     gcloud secrets versions add internal-service-token --data-file=-
   ```

3. 更新所有使用该 secret 的服务（自动使用 `latest`）

4. 验证所有服务正常工作

5. 禁用旧版本:
   ```bash
   gcloud secrets versions disable VERSION_NUMBER \
     --secret=internal-service-token
   ```

## 故障排查

### 检查服务账号权限

```bash
gcloud secrets get-iam-policy internal-service-token \
  --project=xzerolab-480008
```

### 测试 Secret 访问

```bash
gcloud secrets versions access latest \
  --secret=internal-service-token \
  --impersonate-service-account=openclawbot-sa@xzerolab-480008.iam.gserviceaccount.com
```

### 查看审计日志

```bash
gcloud logging read \
  'resource.type="secretmanager.googleapis.com/Secret"
   AND resource.labels.secret_id="internal-service-token"' \
  --limit 50 \
  --project=xzerolab-480008
```
