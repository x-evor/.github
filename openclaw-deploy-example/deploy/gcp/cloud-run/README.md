# Cloud Run 部署指南

本文档说明如何将 OpenClawBot 部署到 Google Cloud Run，并配置默认的 GCS volume 持久化存储。

## 架构概述

- **多阶段构建**: Dockerfile 使用 builder 和 runtime 两个阶段，优化镜像大小
- **GCS 卷挂载**: Cloud Run 默认继续使用 GCS volume 挂载到 `/data`
- **端口配置**: 自动读取 Cloud Run 的 `PORT` 环境变量（默认 8080）
- **健康检查**: 使用 TCP 探针检查 WebSocket 服务可用性

说明：

- Cloud Run 这一路保持现有 GCS volume 默认实现。
- Windows / macOS / Linux 客户端如果需要共享挂载，请改用 `JuiceFS + PostgreSQL + GCS`，不要复用 Cloud Run 的挂载思路。

## 前置条件

1. 安装并配置 Google Cloud SDK
2. 配置环境变量（推荐使用 .env 文件）：

```bash
# 复制示例配置文件
cp .env.example .env

# 编辑 .env 文件，设置必要的环境变量
# 或者直接在命令行设置：
export GCP_PROJECT_ID=xzerolab-480008
export GCP_REGION=asia-northeast1
export GCS_BUCKET_NAME=openclawbot-data
export OPENCLAW_GATEWAY_TOKEN=$(openssl rand -base64 32)
```

**重要环境变量说明：**

| 变量名                   | 说明                 | 默认值                  |
| ------------------------ | -------------------- | ----------------------- |
| `GCP_PROJECT_ID`         | Google Cloud 项目 ID | `xzerolab-480008`       |
| `GCP_REGION`             | 部署区域             | `asia-northeast1`       |
| `GCS_BUCKET_NAME`        | GCS 存储桶名称       | `openclawbot-data`      |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway 认证 token   | 自动生成的 base64 token |
| `SERVICE_ACCOUNT_EMAIL`  | 服务账号邮箱（可选） | 自动生成                |

## 快速部署

### 方式 1: 安全部署（推荐 - 使用 Secret Manager）

使用 Secret Manager 安全存储共享的 `INTERNAL_SERVICE_TOKEN`：

```bash
cd deploy/gcp/cloud-run
chmod +x deploy-secure.sh
./deploy-secure.sh
```

该脚本会自动：

1. 创建/验证 Secret Manager 中的 `internal-service-token`
2. 创建 GCS bucket（如果不存在）
3. 创建服务账号并授予权限（包括 Secret Manager 访问权限）
4. 构建并部署到 Cloud Run，使用 Secret 注入环境变量

### 方式 2: 标准部署（使用环境变量）

```bash
cd deploy/gcp/cloud-run
chmod +x deploy.sh
./deploy.sh
```

该脚本会自动：

1. 创建 GCS bucket（如果不存在）
2. 创建服务账号并授予权限
3. 构建并部署到 Cloud Run

## 手动部署步骤

### 1. 创建 GCS Bucket

```bash
gsutil mb -p ${GCP_PROJECT_ID} -l ${GCP_REGION} gs://${GCS_BUCKET_NAME}
```

### 2. 创建服务账号

```bash
gcloud iam service-accounts create openclawbot-sa \
  --display-name="OpenClawBot Service Account" \
  --project=${GCP_PROJECT_ID}
```

### 3. 授予权限

```bash
gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:openclawbot-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

### 4. 部署到 Cloud Run

```bash
gcloud run deploy openclawbot-svc-plus \
  --source . \
  --platform managed \
  --region ${GCP_REGION} \
  --project ${GCP_PROJECT_ID} \
  --service-account openclawbot-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com \
  --execution-environment gen2 \
  --cpu 2 \
  --memory 4Gi \
  --min-instances 1 \
  --max-instances 10 \
  --no-cpu-throttling \
  --allow-unauthenticated \
  --port 8080 \
  --add-volume name=gcs-data,type=cloud-storage,bucket=${GCS_BUCKET_NAME} \
  --add-volume-mount volume=gcs-data,mount-path=/data
```

## 配置说明

### 环境变量

- `PORT`: Cloud Run 自动设置，应用会自动读取
- `NODE_ENV`: 设置为 `production`
- `OPENCLAW_STATE_DIR`: 设置为 `/data`（GCS 挂载点）

### 资源配置

- **CPU**: 2 核
- **内存**: 4 GiB
- **最小实例数**: 1（保持服务始终运行）
- **最大实例数**: 10
- **CPU 节流**: 禁用（WebSocket 需要持续 CPU）

### 健康检查

- **Startup Probe**: TCP 检查，端口 8080
  - 初始延迟: 10 秒
  - 检查周期: 5 秒
  - 失败阈值: 24 次（允许 2 分钟启动时间）

- **Liveness Probe**: TCP 检查，端口 8080
  - 初始延迟: 60 秒
  - 检查周期: 30 秒
  - 失败阈值: 3 次

## 持久化存储

应用数据存储在 GCS bucket 中，挂载路径为 `/data`。包括：

- 配置文件
- 会话数据
- 日志文件
- 其他运行时数据

## 查看日志

```bash
gcloud run services logs read openclawbot-svc-plus \
  --region ${GCP_REGION} \
  --project ${GCP_PROJECT_ID} \
  --limit 50
```

## 更新服务

修改代码后，重新运行部署脚本或手动部署命令即可。Cloud Run 会自动构建新镜像并滚动更新。

## 故障排查

### 容器启动失败

检查日志：

```bash
gcloud run services logs read openclawbot-svc-plus --region ${GCP_REGION} --limit 100
```

常见问题：

1. **端口配置错误**: 确保应用监听 `PORT` 环境变量指定的端口
2. **权限问题**: 检查服务账号是否有 GCS bucket 访问权限
3. **启动超时**: 增加 startup probe 的 `failureThreshold`

### GCS 挂载问题

验证 bucket 权限：

```bash
gsutil ls -L gs://${GCS_BUCKET_NAME}
```

检查服务账号权限：

```bash
gcloud projects get-iam-policy ${GCP_PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:openclawbot-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
```

## 清理资源

删除 Cloud Run 服务：

```bash
gcloud run services delete openclawbot-svc-plus \
  --region ${GCP_REGION} \
  --project ${GCP_PROJECT_ID}
```

删除 GCS bucket：

```bash
gsutil rm -r gs://${GCS_BUCKET_NAME}
```

删除服务账号：

```bash
gcloud iam service-accounts delete openclawbot-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com \
  --project ${GCP_PROJECT_ID}
```
