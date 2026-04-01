# Deploy XWorkmate Web (xworkmate.svc.plus)

本文档描述如何部署 xworkmate.svc.plus 到 `root@us-xhttp.svc.plus` (5.78.45.49)。

## 目标架构

```
{STABLE_DOMAIN} → CNAME → {RELEASE_DOMAIN} → {DEPLOY_HOST}
                                              ↓
                                         Caddy (80/443)
                                              ↓
                                    xworkmate-web:{host_port}
```

## 端口分配

在 `us-xhttp.svc.plus` 上按顺序分配的 host_port：

| Service | host_port | container_port |
|---------|-----------|----------------|
| accounts | 18080 | 8080 |
| rag-server | 18082 | 8080 |
| x-cloud-flow | 18083 | 8080 |
| x-ops-agent | 18084 | 8080 |
| x-scope-hub | 18085 | 8080 |
| docs | 18086 | 8084 |
| **xworkmate-web** | **18087** | **8080** |

## 部署流程

### 触发工作流

```bash
gh workflow run service_release-xworkmate-web-deploy.yml \
  -f service_ref=main \
  -f run_apply=true
```

### 工作流阶段

| Stage | Name | Description |
|-------|------|-------------|
| 1 | Build Image | 构建 Flutter Web 镜像，推送到 GHCR |
| 2 | Update DNS | CNAME 链: stable-domain → release-domain → us-xhttp.svc.plus (节点 IP) |
| 3 | Deploy | Ansible: 原子化 release，Caddy 反向代理到 xworkmate-web 容器 |
| 4 | Verify | 循环验证直到 https://xworkmate.svc.plus 返回 200 |

### Release Name 格式

```
Release Domain: xworkmate-web-us-xhttp.svc.plus-{git-short-commit}.svc.plus
Stable Domain:  xworkmate.svc.plus
```

每次部署生成唯一的 release domain，旧的 Caddy site config 和容器自动清理。

### 手动部署步骤

#### 1. 构建镜像

```bash
# 在本地构建 Flutter Web
cd ../xworkmate.svc.plus
flutter build web --release

# 或者使用 Docker 多阶段构建
git_sha=$(git rev-parse --short HEAD)
docker build -f lib/web/Dockerfile \
  -t ghcr.io/svc-design/xworkmate-web:${git_sha} \
  lib/web/
docker push ghcr.io/svc-design/xworkmate-web:${git_sha}
```

#### 2. 配置 DNS

```bash
git_sha="abc1234"
release_domain="xworkmate-web-us-xhttp.svc.plus-${git_sha}.svc.plus"

# Cloudflare: release domain CNAME → us-xhttp.svc.plus
curl -X POST "https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_DNS_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"CNAME\",\"name\":\"${release_domain}\",\"content\":\"us-xhttp.svc.plus\",\"ttl\":1,\"proxied\":false}"

# Cloudflare: stable domain CNAME → release domain
curl -X POST "https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_DNS_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"CNAME\",\"name\":\"xworkmate.svc.plus\",\"content\":\"${release_domain}\",\"ttl\":1,\"proxied\":false}"
```

#### 3. SSH 部署

```bash
ssh root@us-xhttp.svc.plus

git_sha="abc1234"
release_name="xworkmate-web-us-xhttp-svc-plus-${git_sha}"
release_dir="/opt/cloud-neutral/xworkmate-web/${release_name}"
mkdir -p "${release_dir}/env"

# 创建 docker-compose.yml
cat > "${release_dir}/docker-compose.yml" << 'EOF'
services:
  app:
    image: ghcr.io/svc-design/xworkmate-web:{tag}
    container_name: {release_name}
    restart: unless-stopped
    ports:
      - "127.0.0.1:18087:8080"
    environment:
      PORT: "8080"
EOF

# 创建 env 文件
cat > "${release_dir}/env/app.env" << 'EOF'
# empty - no env vars needed for static Flutter web
EOF

# 创建 Caddy site config
cat > "/etc/caddy/conf.d/${release_name}.caddy" << 'EOF'
xworkmate-web-us-xhttp.svc.plus-{git_sha}.svc.plus, xworkmate.svc.plus {
  encode zstd gzip
  reverse_proxy 127.0.0.1:18087
}
EOF

# 拉取并启动
cd "${release_dir}"
docker compose pull
docker compose up -d

# 验证 Caddy 配置
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

#### 4. 验证

```bash
# DNS 验证 (stable domain)
dig +short xworkmate.svc.plus
# 期望: us-xhttp.svc.plus 的 IP 或 CNAME

# HTTP 验证
curl -fsSL -o /dev/null -w '%{http_code}' https://xworkmate.svc.plus/
# 期望: 200
```

## 文件清单

| File | Description |
|------|-------------|
| `.github/workflows/service_release-xworkmate-web-deploy.yml` | GitHub Actions 工作流 |
| `ansible/playbooks/deploy_xworkmate_web_compose.yml` | Ansible Playbook |
| `ansible/vars/xworkmate-web.release.public.yml` | Release 公共变量 |
| `ansible/roles/shared_compose_release/` | 共享部署角色 (复用) |
| `ansible/inventory.ini` | 主机清单 (含 [xworkmate-web] 组) |
| `../xworkmate.svc.plus/lib/web/Dockerfile` | Flutter Web Docker 镜像 |

## 故障排查

### 镜像拉取失败

```bash
# 检查 GHCR 登录
docker login ghcr.io -u svc-design

# 手动拉取测试
docker pull ghcr.io/svc-design/xworkmate-web:{git-sha}
```

### DNS 未生效

```bash
# 等待 DNS 传播
dig +short xworkmate.svc.plus
dig +short xworkmate-web-us-xhttp.svc.plus-{git-sha}.svc.plus
```

### 服务无法访问

```bash
ssh root@us-xhttp.svc.plus

# 查看所有 xworkmate-web 容器
docker compose -f /opt/cloud-neutral/xworkmate-web/*/docker-compose.yml ps

# 查看特定 release 日志
release_name="xworkmate-web-us-xhttp-svc-plus-{git-sha}"
docker compose -f "/opt/cloud-neutral/xworkmate-web/${release_name}/docker-compose.yml" logs

# 检查 Caddy 配置
ls -la /etc/caddy/conf.d/ | grep xworkmate

# 验证 Caddy
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

### 清理旧释放

```bash
ssh root@us-xhttp.svc.plus

# 停止并删除旧容器
cd /opt/cloud-neutral/xworkmate-web
for dir in xworkmate-web-*/; do
  if [[ "${dir}" != "xworkmate-web-us-xhttp-svc-plus-{current-sha}/" ]]; then
    echo "Removing old release: ${dir}"
    docker compose -f "${dir}/docker-compose.yml" down
    rm -rf "${dir}"
  fi
done

# 清理旧 Caddy configs
ls /etc/caddy/conf.d/xworkmate*.caddy
```
