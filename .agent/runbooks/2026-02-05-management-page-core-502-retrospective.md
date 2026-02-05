# Dev Issue 回溯：Management 页核心 502 根因

- **事件日期**：2026-02-05（周四）
- **影响页面**：`https://console.svc.plus/panel/management`
- **症状级别**：P1（管理页核心能力不可用）

---

## 1. 用户侧现象（来自现场）

在管理页打开浏览器控制台后，出现两类错误：

1) **核心接口 502**
- `GET /api/admin/users/metrics` -> 502
- `POST /api/admin/users` -> 502

2) **扩展页 404**
- `.../panel/deployments?rsc=...` -> 404
- `.../panel/settings?rsc=...` -> 404
- `.../panel/logs?rsc=...` -> 404
- `.../panel/api-keys?rsc=...` -> 404

管理页表现为：创建用户失败、统计卡片异常、多项管理操作不可用。

---

## 2. 根因拆解（核心 502）

### 根因 A：跨仓接口契约未对齐（`console` 期望存在，`accounts` 未完整暴露）

`console.svc.plus` 管理页 BFF 通过以下路径转发：
- `/api/admin/users/metrics`
- `/api/admin/users`
- `/api/admin/users/:id/pause|resume|renew-uuid`
- `/api/admin/users/:id`（DELETE）
- `/api/admin/blacklist`

这些 BFF 最终代理到 `accounts.svc.plus` 的 `ACCOUNT_API_BASE + /admin/...`。 
其中 `ACCOUNT_API_BASE` 解析为：`/api/auth` 前缀。

**问题点**：`accounts` 当时在 `/api/auth` 作用域下未完整提供对应 `admin` 路由集合，导致上游返回非 JSON/404，BFF 端落入 `invalid_response` 并映射为 502。

> 结论：这是**跨仓 API 路径契约漂移**，不是单仓实现错误。

### 根因 B：`console` 侧 BFF 覆盖不完整（管理动作路由缺口）

管理页前端实际调用了如下 BFF 路由：
- `DELETE /api/admin/users/:id/role`（重置角色）
- `POST /api/admin/users/:id/pause`
- `POST /api/admin/users/:id/resume`
- `DELETE /api/admin/users/:id`
- `POST /api/admin/users/:id/renew-uuid`
- 黑名单增删查

其中部分路由在 BFF 中缺失，会直接 404/405，放大“管理页整体不可用”的体验。

---

## 3. 次生问题（404）

### 根因 C：`/panel/*` 扩展页缺少统一动态分发入口

扩展清单中存在：
- `/panel/deployments`
- `/panel/settings`
- `/panel/logs`
- `/panel/api-keys`

但 App Router 缺少 `src/app/panel/[...segments]/page.tsx` 兜底分发页时，这些扩展路径无法落到 `resolveExtensionRouteComponent(...)`，因此出现 404（含 `?rsc=...` 请求）。

---

## 4. 修复动作（已落地）

## 4.1 accounts.svc.plus

**提交**：`6084f07`  
**标题**：`fix(admin): complete management APIs for console integration`

关键修复：
- 在 `/api/auth` 作用域补齐管理接口（与 console BFF 对齐）：
  - `GET /admin/users/metrics`
  - `POST /admin/users`
  - `POST /admin/users/:id/pause`
  - `POST /admin/users/:id/resume`
  - `DELETE /admin/users/:id`
  - `POST /admin/users/:id/renew-uuid`
  - `GET/POST/DELETE /admin/blacklist...`
- 新增 root-only 自定义 UUID 创建实现（含邮箱/UUID/分组校验、黑名单校验、冲突处理）。

涉及文件：
- `accounts.svc.plus/api/api.go`
- `accounts.svc.plus/api/admin_users.go`
- `accounts.svc.plus/api/admin_users_metrics.go`

验证：
- `go test ./api` 通过。

## 4.2 console.svc.plus

关键修复：
- 补齐 BFF 路由（角色重置 DELETE、pause/resume/delete/renew-uuid、blacklist 增删查）。
- 新增 `src/app/panel/[...segments]/page.tsx` 承接扩展路由并分发到 extension loader。

涉及文件（关键）：
- `console.svc.plus/src/app/api/admin/users/[userId]/role/route.ts`
- `console.svc.plus/src/app/api/admin/users/[userId]/pause/route.ts`
- `console.svc.plus/src/app/api/admin/users/[userId]/resume/route.ts`
- `console.svc.plus/src/app/api/admin/users/[userId]/route.ts`
- `console.svc.plus/src/app/api/admin/users/[userId]/renew-uuid/route.ts`
- `console.svc.plus/src/app/api/admin/blacklist/route.ts`
- `console.svc.plus/src/app/api/admin/blacklist/[email]/route.ts`
- `console.svc.plus/src/app/panel/[...segments]/page.tsx`

验证：
- `yarn typecheck` 通过。

---

## 5. 为什么发布前没拦住

1) **跨仓契约无自动校验**
- `console` 依赖 `accounts` 的 `/api/auth/admin/*` 语义，但缺少契约测试（consumer-driven contract test）。

2) **管理页 E2E 覆盖不足**
- 未覆盖“创建用户 + 角色变更 + 暂停恢复 + 黑名单 + 扩展页导航”这条主链路。

3) **BFF 路由清单未做一致性检查**
- 前端调用点与 `src/app/api/admin/**` 文件树未自动 diff。

---

## 6. 预防改进（建议直接纳入迭代）

### 6.1 契约测试（最高优先）
- 在 `console` 增加契约探测：启动后对 `ACCOUNT_API_BASE` 执行 admin 路由 smoke test。
- 在 `accounts` 增加 API 合同快照，发布前与 `console` 期望对比。

### 6.2 管理页 E2E 主链路
- 新增最小闭环脚本：
  1. 打开 `/panel/management`
  2. 拉取 metrics 成功
  3. 创建自定义 UUID 用户成功
  4. pause/resume/delete 各成功一次
  5. 黑名单 add/remove 成功
  6. 访问 `/panel/deployments|settings|logs|api-keys` 返回 200

### 6.3 路由覆盖守卫
- 增加 CI 检查：扫描 `management.tsx` 中 `fetch('/api/admin/...')`，逐一校验对应 `src/app/api/admin/**/route.ts` 存在且含正确 HTTP 方法。

### 6.4 发布顺序门禁
- 该类跨仓改动必须按顺序发布并打门禁：
  1. `accounts` 先发布（提供接口）
  2. `console` 再发布（消费接口）
  3. 上线后自动执行 smoke

---

## 7. 一页结论（TL;DR）

本次 management 核心 502 的本质是：

- `console` 与 `accounts` 的 **admin API 路径契约漂移**（跨仓）
- `console` BFF 的 **管理动作路由覆盖缺口**（单仓）
- `panel` 扩展路由缺少 `[...]` 分发页导致 **404 次生故障**（单仓）

已通过补齐 `accounts` auth-admin 接口 + 补齐 `console` BFF + 新增 `panel/[...segments]` 分发页完成修复。
