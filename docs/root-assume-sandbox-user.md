# Root Assume Sandbox User 设计说明

本文档定义“root 用户可以直接 assume 到 sandbox 用户、sandbox@svc.plus 无密码仅允许 root 操纵”的端到端设计，并与现有 `console.svc.plus` / `accounts.svc.plus` / agent-xray sync 逻辑对齐。

## 背景与目标

### 现状
- `console.svc.plus` 前端存在 Guest/Demo（演示）只读逻辑，但 `sandbox@svc.plus` 目前主要是前端标记为只读，并没有后端“无密码登录/切换身份”的完整机制。
- `accounts.svc.plus` 后端已经具备：
  - session cookie `xc_session`（基于随机 token + store.Session 持久化）。
  - root 邮箱强约束（`admin@svc.plus`）的管理权限校验。
  - admin sandbox 绑定接口：`GET/POST /api/auth/admin/sandbox/*`（用于绑定某个 agent 为 sandbox 节点）。

### 目标
1. Sandbox 用户与 Demo 用户在产品层面合并：都属于“无需登录的有限条件演示用户”。
   - 对普通访客：仍然是 Guest/Demo 浏览模式（不依赖后端 session）。
   - 对 root 管理员：可以“assume 成 sandbox@svc.plus”在前端以 sandbox 视角操作（但权限仍受 sandbox 账号限制，通常是只读）。
2. root 可以切换身份到 `sandbox@svc.plus`：
   - 只允许 root（`role=root` 且 `email=admin@svc.plus`）触发。
   - 目标用户硬编码白名单，防止 root 任意 impersonate。
3. 保留现有 sidecar / cookie / BFF 代理模式，尽量小改动落地。
4. 附带最少的审计：至少结构化日志；可选 DB audit 表。
5. sandbox 不需要固定 UUID，但需要每小时强制刷新 UUID（proxy_uuid 轮换，expires_at=now+1h）。
6. 当 sandbox 用户绑定某个 agent 节点后：以 `sandbox@svc.plus` 为条件，自动把其 proxy uuid 客户端配置 sync 到该 xray 节点。

## 核心概念

### 身份定义
- **Root 用户**：后端以 `email == admin@svc.plus` 且 `role == root` 作为强约束。
- **Sandbox 用户**：后端以 `email == sandbox@svc.plus` 作为强约束（硬编码）。
- **Guest/Demo（演示）**：面向普通访客，无需登录。可浏览、可生成二维码，但禁止写操作。

### “操纵”含义
- “操纵”不等于赋予 sandbox root 权限。
- “操纵”是：root 可以切换成 sandbox 身份，从 sandbox 视角执行（受 sandbox 权限限制）。

## accounts.svc.plus：后端接口设计

### 1) Root Assume / Revert API

#### 1.1 `POST /api/auth/admin/assume`
- 作用：root 切换为 sandbox 会话。
- 鉴权：必须通过现有 root-only 校验（复用 `requireAdminPermission` 的 root 分支语义：root role + admin@svc.plus）。
- 请求体：
  - `{"email": "sandbox@svc.plus"}`
- 强约束：
  - `email` 必须严格等于 `sandbox@svc.plus`（硬编码白名单）。
- 行为：
  1. 从 store 中查找 sandbox 用户（`GetUserByEmail("sandbox@svc.plus")`）。
     - 若不存在：返回 404（或由运维/初始化脚本创建一次）。
  2. 强制刷新 sandbox 的 ProxyUUID（每小时轮转；过期或为空则更新）。
  3. 创建 sandbox 的 session：`createSession(sandboxUser.ID)`。
- 响应：
  - `{"ok": true, "assumed": "sandbox@svc.plus", "token": "...", "expiresAt": "..." }`

#### 1.2 `POST /api/auth/admin/assume/revert`
- 作用：退出 assume，恢复 root 会话。
- 鉴权：必须 root。
- 行为：accounts 仅做审计日志（best-effort）。
- 响应：
  - `{"ok": true}`

#### 1.3 `GET /api/auth/admin/assume/status`
- 作用：前端展示当前是否处于 assume。
- 鉴权：必须 root。
- 行为：accounts 无法安全读取 console 域的 host-only cookie，因此该端点仅返回 stub（由 console BFF 负责真实状态展示）。

### 2) 只读策略：Sandbox/Demo 合并

在 `isReadOnlyAccount(user)` 中增加：
- `email == sandbox@svc.plus` 视为只读。
- `demo@svc.plus` 保持只读。

这确保：
- root assume 后仍然无法执行写操作（写接口会被 read-only policy 禁止）。

### 3) 最小审计（必做）

在 `assume` / `revert` handler 内打印结构化日志（`slog.Info`）：
- `event`: `admin_assume` / `admin_assume_revert`
- `actor_user_id` / `actor_email`
- `target_user_id` / `target_email`（固定 sandbox）
- `request_ip` / `user_agent`（可选）
- `request_id`（如果已有链路追踪字段）

可选：增加 `assume_audits` 表持久化审计（非本轮必须）。

## console.svc.plus：前端与 BFF 设计

### 1) Next.js BFF 代理路由

新增（或复用已有 admin BFF 模式）三个 API 路由：
- `POST /api/sandbox/assume` -> 代理到 `accounts` 的 `POST /api/auth/admin/assume`，并由 console 写 cookie
- `POST /api/sandbox/assume/revert` -> 使用 host-only `xc_session_root` 恢复 root，并 best-effort 调用 `accounts` 的 `POST /api/auth/admin/assume/revert` 记审计
- `GET /api/sandbox/assume/status` -> 读取 host-only `xc_session_root` 判断状态（不依赖 accounts）

代理时：
- 从 `console` 的 session（`xc_session`）拿到 token，并以 `Authorization: Bearer <token>` 转发。
- **cookie 由 console BFF 写回**：
  - `xc_session`：切换为 sandbox token（可按现有策略设置 domain）
  - `xc_session_root`：host-only 备份 root token（不设置 domain，降低泄露面）

### 2) UI 交互

在控制台增加 root-only 操作入口：
- “切换到 Sandbox（无需密码）”
- “退出 Sandbox”

建议放置位置：
- `/panel/management` 的 root 管理区块
- 或 Header 右上角的 account 菜单里（仅 root 可见）

UI 行为：
1. 点击“切换到 Sandbox”调用 `POST /api/sandbox/assume`。
2. 成功后 `router.refresh()`，并重新拉取 `/api/auth/session`。
3. 页面以 sandbox 身份渲染（前端将显示 guest/readonly banner 或 sandbox banner）。
4. 点击“退出 Sandbox”调用 `POST /api/sandbox/assume/revert` 并刷新。

### 3) 展示提示
- 当 `GET /api/sandbox/assume/status` 返回 `isAssuming=true`：在顶部显示 banner：
  - `当前处于 Assume: sandbox@svc.plus（退出）`

## Agent/Xray：绑定 sandbox 用户到特定节点并自动同步

### 1) 绑定模型
- `accounts.svc.plus` 已有 `sandbox_bindings` 表 + API：
  - `GET /api/auth/admin/sandbox/binding`
  - `POST /api/auth/admin/sandbox/bind`（保存绑定的 agentID）
  - `GET /api/auth/sandbox/binding`（任何已登录用户可读；供 demo/sandbox 用户读取绑定，避免 localStorage）
- `accounts` 内部 `agentRegistry.SetSandboxAgent(agentID, true)` 可记录“哪个 agent 是 sandbox 节点”。

### 2) 同步目标
- 当某个 agent 被标记为 sandbox 节点时：该 agent 运行的 xray config sync 只需要拿到 `sandbox@svc.plus` 的 proxy uuid（无需全量用户）。
- sandbox 不需要固定 UUID，但需要强制刷新：建议 controller 在每次读取 sandbox session 时检查 `proxy_uuid_expires_at`，过期则轮换 `proxy_uuid` 并将过期时间设置为 1 小时后，确保 agent 侧能及时同步最新 UUID。

### 3) Controller API（accounts）补齐

为支撑 agent-xray sync，需要补齐 controller 端接口（当前代码存在 client 调用，但缺少路由实现）：

#### 3.1 `GET /api/agent-server/v1/users`
- 调用方：agent（xray syncer）
- 鉴权：使用 agent token（`Authorization: Bearer <agentToken>`）通过 registry 校验。
- 为支持 shared token：agent 请求需携带 `X-Agent-ID`（或 query `agentId` 兼容）标识具体节点。
- 行为：
  1. 从 token 解出 agent identity（`agentID`）。
  2. 判断该 `agentID` 是否为 sandbox agent（`agentRegistry.IsSandboxAgent(agentID)`）。
  3. 若是 sandbox agent：返回仅包含 sandbox 用户的 `proxy_uuid`：
     - 查询 sandbox 用户（email=sandbox@svc.plus），取 `proxy_uuid` 作为 client ID。
  4. 若不是 sandbox agent：返回“非演示用户”的 clients（建议排除 demo/sandbox 账号，避免污染普通节点）。
- 响应体对齐 `internal/agentproto.ClientListResponse`：
  - `clients: [{ id: <proxy_uuid>, email: <email> }]`
  - `total`
  - `generatedAt`
  - `revision`（可选，后续用于增量/缓存）

#### 3.2 `POST /api/agent-server/v1/status`
- 调用方：agent 心跳
- 鉴权：同上。
- 行为：写入 registry（已有 `registry.ReportStatus` 逻辑）。

> 说明：这两条是“让 sandbox 绑定后自动 sync 到 xray 节点”的关键闭环。

## 安全与边界

1. assume 目标硬编码白名单：仅 `sandbox@svc.plus`。
2. assume/revert/status 必须 root（`admin@svc.plus` + `role=root`）。
3. `xc_session_root` 必须 httpOnly，防止浏览器脚本读取。
4. 建议对 assume/revert 增加基础 CSRF 防护（例如校验 Origin/Referer 为 `https://console.svc.plus`）。

## 测试与验收

### 功能验收
1. root 登录后点击“切换到 Sandbox”：
   - `xc_session` 被替换为 sandbox session。
   - `GET /api/auth/session` 返回 user.email 为 `sandbox@svc.plus`。
2. root 在 sandbox 身份下：写操作被禁止（read-only）。
3. 点击“退出 Sandbox”：恢复 root session。
4. 绑定 sandbox agent 后：
   - sandbox agent 调用 `GET /api/agent-server/v1/users` 只拿到 sandbox 的 proxy uuid。
   - xray syncer 更新配置成功。

### 观测
- Cloud Run logs 中能看到 `admin_assume` / `admin_assume_revert` 的结构化日志。

## 回滚
- 若出现异常：
  - 先禁用 console 的 assume UI（仅前端开关）。
  - 后端 assume API 可保留但不暴露入口；或临时返回 404。
