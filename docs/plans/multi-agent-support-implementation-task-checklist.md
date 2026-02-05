# Multi-Agent Support Implementation - Task Checklist

## 目标

实现多 agent 支持,允许多个 agent 使用共享 token 认证,并持久化到 PostgreSQL

## 已完成任务

1. Agent 端修改 (agent.svc.plus)
   - 添加 AgentID 字段到 `StatusReport` 结构体
   - 修改 `buildStatusReport()` 从配置中提取 agent.id
   - 修改 `runStatusReporter()` 传递 agent ID
   - 确保心跳请求包含 agentId 字段

2. Accounts 端修改 (accounts.svc.plus)
   - 添加 AgentID 字段到 agentproto.StatusReport
   - 实现 `RegisterAgent()` 方法支持动态注册
   - 修改 `agentReportStatusHandler` 提取并使用 agent ID
   - 修改 main.go 使用通配符 credential (ID: "*")

3. 数据库设计
   - 创建 agents 表 schema
   - 添加健康状态和心跳时间字段
   - 创建索引优化查询性能
   - 编写迁移脚本 `20260205_agents_table.sql`

4. 持久化方案设计
   - 设计 Store interface 扩展
   - 规划 PostgreSQL 实现方法
   - 设计异步持久化机制
   - 规划自动清理 stale agents 策略

5. 文档
   - 创建完整的实现计划文档
   - 包含代码示例和配置说明
   - 说明清理策略和配置参数

## 待实施任务

6. Store Interface 实现
   - 扩展 `internal/store/store.go`
   - 添加 Agent 结构体
   - 添加 agent 管理方法到 Store interface
   - 实现 `UpsertAgent()` 方法
   - 实现 `ListAgents()` 方法
   - 实现 `DeleteStaleAgents()` 方法

7. Registry 持久化集成
   - 修改 Registry 添加 store 字段
   - 在 `RegisterAgent()` 中异步持久化
   - 在 `ReportStatus()` 中更新心跳时间
   - 添加错误处理和日志

8. 自动清理任务
   - 实现 `runAgentCleanup()` 后台任务
   - 配置清理间隔和失效阈值
   - 在 main 函数中启动清理任务
   - 添加清理日志和监控

9. 测试
   - 测试多个 agent 同时注册
   - 测试服务重启后 agent 恢复
   - 测试 agent 下线后自动清理
   - 测试心跳更新和健康状态

10. 部署
    - 在本地运行迁移脚本
    - 在生产环境运行迁移
    - 部署更新的 accounts.svc.plus
    - 部署更新的 agent.svc.plus
    - 验证所有 agent 正常工作

## 配置要求

accounts.svc.plus (Cloud Run)
- ✅ INTERNAL_SERVICE_TOKEN - 共享认证 token
- ❌ 不再需要 AGENT_ID (已移除)

agent.svc.plus (各节点)
- ✅ agent.id - 节点自报 ID
- ✅ agent.apiToken - 与 INTERNAL_SERVICE_TOKEN 相同

## 关键设计决策

### 共享 Token 认证

- 所有 agent 使用相同的 INTERNAL_SERVICE_TOKEN
- Agent 在心跳中自报 ID
- accounts.svc.plus 动态注册 agent

### 异步持久化

- 数据库操作异步执行,不阻塞心跳
- 失败容忍,数据库错误不影响功能
- 内存 registry 仍是主要数据源

### 自动清理

- 10 分钟未心跳视为下线
- 每 5 分钟执行一次清理
- 可通过环境变量配置

## 验证步骤

- 检查 agent 心跳日志显示正确的 agent ID
- 查询数据库确认 agent 已注册
- 停止 agent,等待 10 分钟,确认自动清理
- 重启 accounts.svc.plus,确认 agent 信息恢复
