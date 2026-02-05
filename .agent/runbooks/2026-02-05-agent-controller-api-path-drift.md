# Runbook: Agent 控制器 API 路径漂移（/api/agent-server/v1 vs /api/agent/v1）

- 日期：2026-02-05
- 影响：`/panel/agent` 页面异常、节点不可见、Agent 周期上报失败
- 症状：
  - Agent 日志持续出现 `controller returned 404 Not Found`
  - `xray config sync failed` / `failed to report agent status`
  - 前端因节点数据异常触发客户端异常（历史上出现过 `forEach is not a function`）

## 根因

跨环境 API 路径不一致：

- 部分环境暴露：`/api/agent-server/v1/*`
- 部分环境仍是：`/api/agent/v1/*`

Agent 端若只调用其中一套路径，在另一环境会持续 404，导致：

1. 拉取 users 失败
2. status 上报失败
3. console 节点展示和 VLESS 构建数据不稳定

## 处置（已验证）

1. **Agent 客户端做路径回退**（首选新路径，404 时回退旧路径）
   - `GET users`: `/api/agent-server/v1/users` -> 404 时回退 `/api/agent/v1/users`
   - `POST status`: `/api/agent-server/v1/status` -> 404 时回退 `/api/agent/v1/status`
2. **Console 节点页做防御性解析**
   - 非数组 payload 不再直接 `forEach`
   - 显示错误提示并避免页面崩溃

## 验证步骤

### A. Controller 端路由探测

```bash
curl -i https://<controller>/api/agent-server/v1/users
curl -i https://<controller>/api/agent/v1/users
curl -i -X POST https://<controller>/api/agent-server/v1/status
curl -i -X POST https://<controller>/api/agent/v1/status
```

### B. Agent 端日志

```bash
journalctl -fu agent-svc-plus
```

期望：不再出现持续 404；周期性 sync/status 正常。

### C. Console 页面

访问：`https://www.svc.plus/panel/agent`

期望：
- 页面不崩溃
- 节点列表可显示或明确错误提示

## 预防机制（必须执行）

1. **统一契约文档**：只保留一个 canonical 路径（推荐 `/api/agent-server/v1/*`）。
2. **兼容窗口策略**：保留旧路径一段时间（至少 1~2 个发布周期），并在日志中标记 deprecated。
3. **发布前 smoke**：将两套路径探测加入 CI/发布脚本，任一失败即阻断上线。
4. **前端守卫**：所有节点 API 消费方必须做 payload schema 校验（数组/对象兼容 + 错误展示）。

## 回滚方案

1. 回滚 agent 到上一个稳定二进制
2. 恢复 controller 旧路径映射
3. 保持 console 防御性解析不回滚（防止再次白屏）
