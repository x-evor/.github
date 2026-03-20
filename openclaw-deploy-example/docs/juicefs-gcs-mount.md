# Windows / macOS / Linux 共享挂载方案（JuiceFS + PostgreSQL + GCS）

本文档定义新的默认共享挂载架构，用于替代直接使用 `gcsfuse` 或 `rclone` 挂载 GCS bucket 的方式。

## 推荐架构

```txt
Windows / macOS / Linux 客户端
        │
   JuiceFS Client
        │
 PostgreSQL（元数据，自建）
        │
对象存储（GCS）
```

默认建议：

- `PostgreSQL` 放在一台 7x24 在线的 Linux 主机或 VPS 上，不要放在日常会休眠的桌面端。
- `GCS` 只负责对象块存储，不负责目录、inode、锁和 POSIX 元数据。
- `openclaw-local.svc.plus` 仍然建议本地磁盘优先；`/opt/data` 或 `/data` 只在你明确需要共享挂载时使用。
- Cloud Run 保持现有 GCS volume 默认实现；本文档只覆盖 Windows/macOS/Linux 主机和客户端。

## 为什么替代 gcsfuse / rclone

直接把 GCS bucket 挂成文件系统时：

- 目录和文件元数据仍然来自对象存储语义，不是真正的 POSIX 元数据层。
- 多客户端并发写入时，锁、rename、元数据一致性和小文件体验都比较脆弱。
- `rclone nfsmount` 在 macOS 上本质是额外套了一层 NFS 转发，故障面更多。

`JuiceFS` 的思路不同：

- `PostgreSQL` 保存 inode、目录树、权限、锁和文件映射。
- `GCS` 只保存对象数据块。
- 客户端统一用 `juicefs mount`，Windows/macOS/Linux 共享同一套元数据视图。

## PostgreSQL 放置建议

推荐优先级：

1. 单台长期在线的 Linux VPS，和主要 OpenClaw 网关放在同一地域。
2. 已有自建数据库主机时，直接复用该 PostgreSQL 实例，单独创建 `openclawfs` 数据库和用户。
3. 如果后续不想自运维，再迁移到托管 PostgreSQL；对象存储层仍然可以保持 GCS 不变。

不建议：

- 把 PostgreSQL 放在 macOS 笔记本本地。
- 把 PostgreSQL 跟临时测试容器绑在一起然后让多个客户端长期依赖。

## 前置条件

1. 一个已有的 GCS bucket，例如 `openclawbot-data`
2. 一个 PostgreSQL 数据库和用户
3. GCS 认证
   - GCP VM 上可直接使用绑定服务账号
   - 非 GCP 主机建议使用 `GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json`
4. 客户端 FUSE 依赖
   - macOS: `macFUSE`
   - Linux: `fuse3`
   - Windows: `WinFsp`

PostgreSQL 初始化示例：

```sql
CREATE DATABASE openclawfs;
CREATE USER openclaw WITH PASSWORD '<postgres-meta-password>';
GRANT ALL PRIVILEGES ON DATABASE openclawfs TO openclaw;
```

## 安装 JuiceFS

### macOS

```bash
brew install juicefs
brew install --cask macfuse
```

### Linux

```bash
curl -sSL https://d.juicefs.com/install | sh -s -- /usr/local/bin
```

### Windows

- 先安装 `WinFsp`
- 再安装 `juicefs.exe`

## 首次格式化文件系统

只需要执行一次。

```bash
export META_PASSWORD='<postgres-meta-password>'
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcp/openclaw-sa.json"

juicefs format \
  --storage gs \
  --bucket openclawbot-data \
  "postgres://openclaw@pg.internal:5432/openclawfs?sslmode=disable" \
  openclawfs
```

说明：

- `META_PASSWORD` 用来给 PostgreSQL 元数据连接补密码，避免把密码直接塞进 URL。
- 文件系统名这里示例为 `openclawfs`，后续所有客户端挂载同一个元数据地址即可。

## macOS / Linux 挂载

仓库内置了一个轻量脚本：

```bash
sudo mkdir -p /opt/data
sudo chown "$USER":"$(id -gn)" /opt/data
chmod +x scripts/mount_juicefs_openclaw.sh

export JUICEFS_META_URL='postgres://openclaw@pg.internal:5432/openclawfs?sslmode=disable'
export META_PASSWORD='<postgres-meta-password>'
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcp/openclaw-sa.json"

./scripts/mount_juicefs_openclaw.sh up \
  --bucket openclawbot-data \
  --mount-point /opt/data
```

常用命令：

```bash
./scripts/mount_juicefs_openclaw.sh format --bucket openclawbot-data --meta-url "$JUICEFS_META_URL"
./scripts/mount_juicefs_openclaw.sh status --mount-point /opt/data
./scripts/mount_juicefs_openclaw.sh ensure --mount-point /opt/data
./scripts/mount_juicefs_openclaw.sh down --mount-point /opt/data
./scripts/mount_juicefs_openclaw.sh restart --mount-point /opt/data
```

如果你明确要让 OpenClaw 把共享挂载作为运行状态目录，再设置：

```bash
export OPENCLAW_STATE_DIR=/opt/data
```

否则更推荐：

- 热状态继续放本地磁盘
- `/opt/data` 只用于共享 workspace、共享产物、恢复入口或显式同步

## 单机 / VPS 自动化部署

`scripts/setup.sh` 已切换到 `JuiceFS + PostgreSQL + GCS`：

```bash
curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/setup.sh \
  | bash -s -- --mode vps \
    --domain openclaw-vps.svc.plus \
    --bucket openclawbot-data \
    --meta-url "postgres://openclaw@pg.internal:5432/openclawfs?sslmode=disable" \
    --meta-password "<postgres-meta-password>" \
    --gcs-credentials "/root/.config/gcp/openclaw-sa.json" \
    --gateway-token "<token>" \
    --zai-api-key "<key>"
```

该脚本会：

- 安装 `juicefs`
- 首次检查并格式化文件系统
- 生成 systemd mount service，把 `JuiceFS` 挂到 `/data`
- 在挂载后的 `/data` 上生成 `openclaw` 配置和 workspace

## Windows 挂载

Windows 侧保持同一个元数据地址即可，例如挂到 `J:`：

```powershell
$env:META_PASSWORD = "<postgres-meta-password>"
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\openclaw\openclaw-sa.json"
juicefs.exe mount "postgres://openclaw@pg.internal:5432/openclawfs?sslmode=disable" J:
```

## 验证清单

```bash
./scripts/mount_juicefs_openclaw.sh status --mount-point /opt/data
mount | grep " on /opt/data "
touch /opt/data/.rw-check && rm -f /opt/data/.rw-check
```

重点检查：

- 同一个目录在不同客户端可见
- 小文件创建、删除、rename 正常
- PostgreSQL 可持续连通
- GCS 凭据有效，且 bucket 可写
