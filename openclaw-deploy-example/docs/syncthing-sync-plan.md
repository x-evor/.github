# OpenClaw Syncthing 同步方案

本文件对应 [OpenClaw 多节点存储场景矩阵](storage-sync-scenarios.md) 的场景 1 实施细则。

本文档定义 macOS 本机和 VPS 之间基于 Syncthing 的同步边界。

目标不是把整棵 `/opt/data` 做成全量双向镜像，而是只同步明确允许共享的数据平面。

默认角色分工：

- VPS 作为主 Gateway 节点，承担 7x24 在线入口和默认远程执行。
- macOS 作为本地交互节点，承担浏览器态、桌面自动化和低延迟人工交互。
- Syncthing 只负责同步共享数据目录，不负责解决多节点运行时并发。
- 适用范围限定为：2 节点、单操作者、低并发。

## 同步矩阵

| 数据类型 | 配置路径 | 共享状态 | 说明 |
| :------- | :------- | :------- | :--- |
| Sessions | `/opt/data/sessions` | ✅ 共享 | 跨节点同步会话状态 |
| Workspace | `/opt/data/workspace` | ✅ 共享 | 工作文件、项目代码 |
| Memory | `/opt/data/memory` | ✅ 共享 | 记忆、笔记、上下文 |
| Temp | `~/.openclaw/tmp` | ❌ 节点本地 | 临时文件、执行缓存 |
| Logs | `~/.openclaw/logs` | ❌ 节点本地 | 节点独立日志 |
| Browser | 内部管理 | ❌ 节点本地 | CDP 状态不共享 |
| Live WS | 运行时内存 | ❌ 节点本地 | 运行时状态 |

补充约束：

- 不要把整棵 `/opt/data` 作为一个 Syncthing 根目录直接双向同步。
- 推荐拆成三个独立 Syncthing folder：
  - `openclaw-sessions` -> `/opt/data/sessions`
  - `openclaw-workspace` -> `/opt/data/workspace`
  - `openclaw-memory` -> `/opt/data/memory`
- `openclaw.json`、`identity/`、`devices/`、`credentials/`、`browser/`、`.openclaw/` 继续保持节点本地，不进入 Syncthing。

## 为什么要拆成 3 个 folder

如果直接同步 `/opt/data` 根目录，会把以下运行态也一起卷进去：

- 浏览器 profile
- 节点认证信息
- 设备配对信息
- 临时文件
- 日志
- 本地缓存

这些内容在 macOS 和 VPS 之间没有共享价值，反而会制造冲突、权限漂移和脏状态传播。

拆成独立 folder 后：

- 共享边界清晰
- 冲突影响面更小
- 可以按目录单独设置 ignore、版本回收和重扫策略

## Sessions 设计

推荐：

- Syncthing folder: `openclaw-sessions`
- Path: `/opt/data/sessions`
- Folder type: `Send & Receive`
- File versioning: `Staggered File Versioning`

约束：

- 同一个 session 文件只能有一个活动写入节点。
- 另一个节点可以读取已落盘的会话状态，但不要同时改写同一个活跃 session。
- 如果后续会话文件是 append-only 的 `jsonl` 或分片文件，这一层更稳定。

不建议：

- 两个节点同时写同一个会话文件。
- 依赖 Syncthing 去解决会话级并发。

## Workspace 设计

推荐：

- Syncthing folder: `openclaw-workspace`
- Path: `/opt/data/workspace`
- Folder type: `Send & Receive`
- Ignore 临时构建目录和 Git 锁文件

约束：

- `workspace` 可以共享，但不能把它当成两个节点同时在线改同一任务的 live working tree。
- Git 仍然是代码合并和冲突解决边界。
- 最稳的执行方式是：
  - 同一个任务只在一个节点上活跃写入
  - 任务完成后通过 Git commit / branch / patch 做明确合并

建议排除：

- `**/.git/index.lock`
- `**/.git/refs/**`
- `**/.git/logs/**`
- `**/node_modules/**`
- `**/.next/**`
- `**/dist/**`
- `**/build/**`
- `**/.DS_Store`

## Memory 设计

推荐：

- Syncthing folder: `openclaw-memory`
- Path: `/opt/data/memory`
- Folder type: `Send & Receive`
- 内容尽量采用 `md`、`json`、`jsonl`、分片快照

推荐目录结构：

```text
/opt/data/memory/
├── db/                          # 本地 SQLite（不同步）
│   └── memory.db -> 改为节点本地路径
│       ~/.openclaw/memory.db
├── notes/                       # Markdown 文件（同步）
│   ├── 2026-03-11.md
│   ├── MEMORY.md
│   └── index.json
└── attachments/                 # 附件（同步）
    └── ...
```

关键约束：

- 不要把单文件 SQLite 当作多节点双向同步的数据格式。
- SQLite 应迁到节点本地，例如 `~/.openclaw/memory.db`。
- 当前如果存在 `main.sqlite`、`*.db`、`*.sqlite-journal`、`*.wal`，应排除在 Syncthing 之外。

建议排除：

- `main.sqlite`
- `**/*.sqlite`
- `**/*.sqlite-*`
- `**/*.db`
- `**/*.db-*`
- `**/*.tmp`
- `**/*.lock`

如果需要共享长期记忆，优先使用：

- `memory/notes/**/*.md`
- `memory/notes/**/*.json`
- `memory/notes/**/*.jsonl`
- `memory/attachments/**`
- `memory/summaries/**`
- `memory/snapshots/**`

不建议在这个场景下做的事：

- 不要把 `memory.db`、`main.sqlite`、`*.db` 放进 Syncthing
- 不要把 Syncthing 当成多节点并发 memory 数据库
- 当活跃节点超过 2 个或开始多人并发写 memory 时，应升级到 [场景 2](storage-sync-scenarios.md)

## 节点本地目录

以下内容保持节点本地，不参与 Syncthing：

- `~/.openclaw/tmp`
- `~/.openclaw/logs`
- 浏览器内部数据目录
- 本地运行中的 Live Workspace 状态
- `/opt/data/browser`
- `/opt/data/.openclaw`
- `/opt/data/identity`
- `/opt/data/devices`
- `/opt/data/credentials`
- `/opt/data/openclaw.json`

## 推荐配置

### 设备角色

- macOS: `Introducer = false`
- VPS: `Introducer = false`
- 两端都使用 `Send & Receive`

### Gateway 角色

- VPS: 主 Gateway 节点
- macOS: 本地优先交互节点
- Cloud Run: 可选 overflow / failover 节点

推荐执行策略：

- 默认在线任务在 VPS 执行
- 浏览器态和桌面态任务在 macOS 执行
- 共享目录同步完成后再切换任务执行节点

### 冲突策略

- 开启 `Staggered File Versioning`
- 保留 Syncthing 冲突文件，不自动覆盖
- 发现冲突后人工合并，再删掉冲突副本

### 扫描与恢复

- 开启 `Watch for Changes`
- `Rescan Interval` 设成较长周期，避免无意义全量扫描
- 笔记本从休眠恢复后，优先等本地运行态稳定，再让 Syncthing 补同步

### Ignore 模板

`/opt/data/workspace/.stignore`：

```text
(?d)**/.git/index.lock
(?d)**/.git/refs
(?d)**/.git/logs
(?d)**/node_modules
(?d)**/.next
(?d)**/dist
(?d)**/build
(?d)**/.DS_Store
```

`/opt/data/memory/.stignore`：

```text
(?d)db
(?d)**/*.sqlite
(?d)**/*.sqlite-*
(?d)**/*.db
(?d)**/*.db-*
(?d)**/*.tmp
(?d)**/*.lock
```

## 实施计划

### Phase 0: 现状冻结

目标：

- 停止继续尝试同步整棵 `/opt/data`
- 记录当前 macOS 和 VPS 的目录状态
- 先把 VPS 明确为主 Gateway 节点

检查项：

- `openclaw.svc.plus` 当前默认指向 VPS
- macOS 仅作为本地交互节点
- 现有 `/opt/data` 已完成备份或至少保留快照

### Phase 1: 目录拆分和本地化

目标：

- 把可共享目录和节点本地目录分开
- 把 SQLite 从共享目录移走

操作：

1. 在所有节点创建目录：

```bash
sudo mkdir -p /opt/data/{sessions,memory,workspace,tmp,logs}
sudo chown -R "$(whoami)":"$(id -gn)" /opt/data
mkdir -p ~/.openclaw/{tmp,logs}
mkdir -p ~/.openclaw
```

2. 将本地配置文件放到节点本地：

```bash
cp openclaw.json ~/.openclaw/openclaw.json
```

3. 迁移本地 SQLite：

```bash
mkdir -p ~/.openclaw
# 旧路径示例
# /opt/data/memory/db/memory.db
# 新路径
# ~/.openclaw/memory.db
```

4. 确认 `/opt/data/memory` 只保留 `notes/`、`attachments/`、`summaries/`、`snapshots/` 等可同步内容。

### Phase 2: Syncthing 部署

目标：

- 在 macOS 和 VPS 上安装并拉起 Syncthing
- 建立 3 个独立共享 folder

操作：

1. 安装 Syncthing：

```bash
# macOS
brew install syncthing

# Ubuntu
sudo apt install syncthing
```

2. 配置三个 Syncthing folder：

- `openclaw-sessions` -> `/opt/data/sessions`
- `openclaw-workspace` -> `/opt/data/workspace`
- `openclaw-memory` -> `/opt/data/memory`

3. 为 `workspace` 和 `memory` 放置 `.stignore`。

4. 启动 Syncthing：

```bash
syncthing serve --no-browser &
```

5. 在 `http://127.0.0.1:8384` 确认三个共享目录都已 `Up to Date`。

### Phase 3: Gateway 切换与验证

目标：

- 让 VPS 稳定作为主 Gateway
- 验证共享目录能被两端读取
- 不把节点本地运行态带进同步面

操作：

1. 同步完成后再重启网关进程：

```bash
openclaw gateway restart
```

2. 做跨节点验证：
   - 节点 A 写入 `sessions` / `workspace` / `memory/notes`
   - 节点 B 确认文件可见
   - 节点 B 写入 `memory/attachments`
   - 节点 A 确认文件可见
   - 不要用两个节点同时写同一个 session 文件或同一个任务工作树

3. 做角色验证：
   - `openclaw.svc.plus` 默认请求落在 VPS
   - 本地浏览器态任务仍在 macOS 执行
   - 关闭 macOS Syncthing 后，VPS 主 Gateway 仍可工作

### Phase 4: 稳定化

目标：

- 降低 Syncthing 冲突和抖动
- 把“共享目录”和“节点本地目录”固定下来

操作：

1. 开启 `Staggered File Versioning`
2. 保留冲突副本，不自动清理
3. 观察一段时间后再决定是否细化 `workspace` 子目录
4. 如果 `sessions` 出现并发冲突，改成按节点或任务分片

## 验收标准

- `sessions`、`workspace`、`memory` 三个 Syncthing folder 都保持 `Up to Date`
- `~/.openclaw/memory.db` 为节点本地文件，不再出现在共享目录
- `/opt/data/memory/notes` 和 `/opt/data/memory/attachments` 可双向可见
- `/opt/data/browser`、`~/.openclaw/tmp`、`~/.openclaw/logs` 没有进入 Syncthing
- VPS 作为主 Gateway 时，macOS 离线不会影响远程入口可用性
- macOS 作为交互节点时，浏览器态仍只在本地执行

## 回滚计划

- 如果 `workspace` 冲突过多，先暂停 `openclaw-workspace` folder，只保留 `sessions` 和 `memory`
- 如果 `memory` 仍依赖 SQLite，暂停 `openclaw-memory` folder，先只同步 `notes/` 和 `attachments/`
- 如果 Syncthing 带来明显脏状态，恢复到“VPS 主 Gateway + macOS 本地交互 + Git/MemOS 边界同步”的保守模式

## 最终原则

- Sessions 可以共享，但单个活跃 session 只能单写。
- Workspace 可以共享，但 Git 仍是合并边界。
- Memory 可以共享，但不要双向同步 SQLite。
- VPS 是主 Gateway 节点，macOS 是交互节点。
- Temp、Logs、Browser、Live WS 继续保持节点本地。
- Syncthing 用来同步共享目录，不用来把 OpenClaw 变成 full-state multi-writer 系统。
