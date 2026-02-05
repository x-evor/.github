# Skill: agent-controller-api-compat

## Purpose

避免 Agent 与 Controller 因 API 路径差异导致的 404/白屏类事故。

## Trigger

出现以下任一现象时立即使用本技能：

- Agent 日志包含 `controller returned 404`（users/status）
- `/panel/agent` 页面节点异常或 client-side exception
- 新环境切换 controller 地址后节点全量离线

## Canonical Contract

- 推荐标准路径：`/api/agent-server/v1/*`
- 兼容旧路径：`/api/agent/v1/*`（仅在迁移窗口内保留）

## Mandatory Checks

1. **Controller route probe**
   - `GET /api/agent-server/v1/users`
   - `POST /api/agent-server/v1/status`
   - `GET /api/agent/v1/users`
   - `POST /api/agent/v1/status`
2. **Agent fallback behavior**
   - 首路径 404 时，自动尝试兼容路径
3. **Console payload safety**
   - 节点接口返回非数组时不崩溃，需回退为空列表并展示错误
4. **Observability**
   - 日志中区分 `404 fallback` 与 `hard failure`

## Implementation Rules

- Agent 客户端调用 controller endpoint 必须支持路径回退（至少覆盖 users/status）。
- 新增/调整路径时必须同步：
  - `docs/api/*`
  - 发布检查清单
  - E2E smoke 脚本
- 前端消费节点 API 时必须做 schema 验证，禁止直接假设数组结构。

## Release Gate (Do not bypass)

上线前必须同时满足：

- Agent 端 `go test ./...` 通过
- Console 端 `yarn typecheck` 通过
- 真实环境 smoke：`/panel/agent` 可打开且无 client exception
- Agent 日志 5 分钟内无连续 404（users/status）
