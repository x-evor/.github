# OpenClaw 多节点存储场景矩阵

本文档用于在 30 秒内判断当前部署应该选哪条路：

- 场景 1：`macOS 本地 + svc.plus 远程` 的 2 节点方案，推荐 `Syncthing + 本地 SQLite`
- 场景 2：`3+ 节点 / 团队协作` 的多节点方案，推荐 `PostgreSQL`

注意：

- 本文中的 YAML / JSON 片段只用于架构示意，不代表当前 repo 已实现这些配置字段。
- 本文只覆盖 `memory` 的存储决策，不把整个 OpenClaw 运行态改成共享多写系统。

## 快速对比

| 场景 | 节点数 | Memory 后端 | 并发写入能力 | 运维复杂度 | 故障恢复方式 | 推荐对象 |
| :--- | :----- | :---------- | :----------- | :--------- | :----------- | :------- |
| 场景 1 | 2 个节点 | Syncthing + 本地 SQLite | 低，依赖单写约束 | 低 | 节点本地缓存 + Syncthing 补同步 | 个人使用、单操作者 |
| 场景 2 | 3+ 活跃节点 | PostgreSQL | 中高，支持集中一致性 | 中 | 数据库备份 / 恢复 + 节点重连 | 团队协作、多人并发 |

## 共同约束

不管选哪个场景，下列规则都不变：

- `workspace` 仍以 Git 为合并边界，不是可安全双写的 live working tree。
- `sessions` 本轮仍按共享文件 + 单 session 单写约束处理，不扩展成数据库化 session 方案。
- 浏览器态、`tmp`、`logs`、节点身份配置、live workspace 运行态继续保持节点本地。
- `memory` 的选择只解决记忆数据的共享与一致性，不等于整个 Gateway 变成 full-state multi-writer 系统。

## 场景 1：macOS 本地 + svc.plus 远程

### 适用条件

- 只有 2 个节点：1 台 macOS + 1 台 VPS
- 主要操作者是一个人
- 需要保留本地交互能力，同时让远端保持 7x24 在线
- 可以接受 `sessions` 和 `workspace` 的单写约束

### 推荐方案

- `memory`：`/opt/data/memory` 共享 Markdown / JSON / JSONL / attachments
- `memory.db`：节点本地，例如 `~/.openclaw/memory.db`
- `sync.provider`：Syncthing

示意配置：

```yaml
storage:
  memory:
    type: file
    path: /opt/data/memory
    dbPath: ~/.openclaw/memory.db
  sync:
    enabled: true
    provider: syncthing
```

### 为什么推荐

- 运维简单，不需要单独维护数据库
- 2 节点规模下，本地缓存和文件同步已经足够
- 节点离线时风险较低，恢复后可重新同步共享目录

### 同步边界

- 共享：
  - `/opt/data/sessions`
  - `/opt/data/workspace`
  - `/opt/data/memory`
- 其中 `memory` 只同步：
  - `notes/`
  - `attachments/`
  - `summaries/`
  - `snapshots/`
- 节点本地：
  - `~/.openclaw/memory.db`
  - 浏览器态
  - `~/.openclaw/tmp`
  - `~/.openclaw/logs`
  - `identity` / `devices` / `credentials`

### 主节点角色

- VPS：主 Gateway 节点，负责默认远程入口和在线执行
- macOS：本地交互节点，负责浏览器态、桌面自动化和人工介入任务

### 失败模式

- Syncthing 冲突文件：通常出现在两端同时改写同一个 session 文件或同一个 workspace 任务目录
- 笔记本休眠后短时滞后：恢复后需要等待 Syncthing 补同步
- SQLite 误入共享目录：会导致数据库损坏或反复冲突

### 何时升级到场景 2

- 出现 3 个以上活跃节点
- 有多人同时写入记忆数据
- 需要集中备份、审计、恢复，而不想依赖节点各自缓存
- `memory` 层开始需要真正的并发一致性

实施细则见 [OpenClaw Syncthing 同步方案](syncthing-sync-plan.md)。

## 场景 2：3+ 节点 / 团队协作

### 适用条件

- 3 个以上活跃节点
- 多个操作者或多个服务同时写入记忆数据
- 需要集中备份、审计、权限管理或统一恢复点

### 推荐方案

- `memory backend`：PostgreSQL
- 每个节点保留唯一 `nodeId`
- `sessions` 继续共享文件，但保留单 session 单写
- `workspace` 继续走 Git，同步边界不变

示意配置：

```yaml
memory:
  backend: postgres
  postgres:
    url: postgresql://openclaw:password@db.svc.plus:5432/memory
  distributed:
    enabled: true
    nodeId: mac-shenlan
```

### 为什么推荐

- 记忆数据可以集中备份和统一恢复
- 支持比 Syncthing 更强的并发一致性与集中治理
- 适合多人协作和多节点在线写入

### 同步边界

- 进入 PostgreSQL：
  - `memory` 结构化数据
  - 记忆索引、摘要、检索元数据
- 不进入 PostgreSQL：
  - 浏览器态
  - `logs` / `tmp`
  - live workspace 运行态
  - 节点身份配置
  - `workspace` Git 工作树
- 继续保留原共享方式：
  - `sessions` 仍是共享文件
  - `workspace` 仍通过 Git 边界同步
  - `notes/attachments` 可暂时保留 Syncthing 或对象存储，直到后续有专门后端

### 主节点角色

- VPS：仍然是主 Gateway 节点
- 其他节点：按 `nodeId` 独立接入
- macOS：继续承担交互节点角色，不因为 PostgreSQL 而获得浏览器态共享能力

### 失败模式

- PostgreSQL 不可用：`memory` 读写受影响，需要降级或暂存
- 配置漂移：多个节点的 `nodeId` 冲突或连接串不一致
- 团队误解：把 PostgreSQL 当成 `workspace` 协同编辑层，导致 live working tree 仍然并发冲突

### 迁移路径

1. 先把 `memory.db` 从 `/opt/data/memory` 隔离到 `~/.openclaw/memory.db`
2. 保留 `notes/attachments` 的 Syncthing，共享能力先不回退
3. 部署 PostgreSQL，并准备 `memory backend` 配置
4. 做一次性迁移：
   - 从 SQLite 导出结构化 memory 数据
   - 将已有 Markdown / JSONL 做回填整理
   - 导入 PostgreSQL
5. 切换顺序固定为：
   - `VPS` 先切到 PostgreSQL
   - 验证成功后，再切 `macOS`
6. 回滚固定为：
   - 保留 SQLite 快照
   - 保留 Syncthing 的 `notes/attachments`
   - 只回退 `memory backend`，不回退共享目录层

### 何时不该选场景 2

- 只有 2 个节点
- 只有单操作者
- 还没有多人并发写 memory 的需求
- 团队不想增加数据库运维面

## 推荐结论

- 当前如果是“本地 Mac + svc.plus 远程”两节点形态，优先用场景 1。
- 当前如果已经进入“3+ 节点 / 团队协作 / 多人并发写 memory”，再切到场景 2。
- 两个场景都不支持“整棵 `/opt/data` 安全双向同步”或“SQLite 分布式双写”。
