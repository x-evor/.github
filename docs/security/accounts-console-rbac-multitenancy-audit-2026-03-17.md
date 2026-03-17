# Accounts + Console RBAC / 多租户 / Token 审计报告

**Date**: 2026-03-17  
**Status**: Completed  
**Audited Repos**:
- `accounts.svc.plus`
- `console.svc.plus`

## Executive Summary

本次联动审计确认：

- `accounts.svc.plus` 已落地一版可运行的全局 RBAC，但仍是单租户风格的全局用户模型。
- `console.svc.plus` 已经在 session、访问控制和 UI 语义上预留了 `tenantId / tenants / permissions`，但 `accounts.svc.plus` 当前没有对应的持久化租户模型。
- 当前 API token 体系同时存在会话 token、JWT refresh、OAuth 一次性 `exchange_code -> token/exchange`、`INTERNAL_SERVICE_TOKEN` 和多类外部集成 token，边界仍未完全统一。
- 当前最高风险不是“没有 RBAC”，而是“RBAC 已实现一半，但租户边界、token 信任边界和 console BFF 权限收口没有完全对齐”。

## Scope And Evidence

本报告仅基于已存在的代码、schema 和文档，不推测未实现能力。

核心证据：

- `accounts.svc.plus/sql/schema.sql`
- `accounts.svc.plus/api/api.go`
- `accounts.svc.plus/api/admin_users_metrics.go`
- `accounts.svc.plus/internal/auth/token_service.go`
- `accounts.svc.plus/internal/auth/middleware.go`
- `accounts.svc.plus/internal/store/store.go`
- `console.svc.plus/src/server/account/session.ts`
- `console.svc.plus/src/lib/userStore.ts`
- `console.svc.plus/src/lib/accessControl.ts`
- `console.svc.plus/src/app/api/admin/**`
- `console.svc.plus/src/server/consoleIntegrations.ts`

## Current State

### 1. `accounts.svc.plus`: 已实现能力

已实现的数据模型：

- `users`
- `sessions`
- `identities`
- `subscriptions`
- `rbac_roles`
- `rbac_permissions`
- `rbac_role_permissions`
- `admin_settings`
- `agents`
- `nodes`

已实现的授权模型：

- 全局角色：`root / admin / operator / readonly / user`
- 全局权限：`users.permissions JSONB` + `rbac_permissions`
- 关键授权入口：`requireAdminPermission`
- `operator` 还会叠加 `admin_settings` 的动态权限矩阵

已实现的认证/凭证模型：

- 默认会话 token：`xc_session`
- 可选 JWT：`access_token / refresh_token`
- OAuth 一次性 `exchange_code -> token/exchange`
- 内部服务 token：`X-Service-Token` / `INTERNAL_SERVICE_TOKEN`
- OAuth identity 绑定：GitHub / Google

关键结论：

- 这是“全局用户 + 全局角色 + 全局权限”模型，不是“tenant-scoped RBAC”。
- `sanitizeUser` 当前返回 `groups / permissions / proxyUuid`，但不返回真实租户成员关系。
- `sessions` 仅绑定 `user_uuid`，没有 tenant 上下文。

### 2. `accounts.svc.plus`: 未实现能力

未看到已落地的实体或关系：

- `tenant`
- `organization`
- `workspace`
- `tenant_membership`
- `tenant_role_binding`
- `tenant-scoped token`
- `component-scoped credential ownership`

这意味着当前后端不能原生表达：

- 一个用户属于多个 tenant
- 同一用户在不同 tenant 中拥有不同角色
- 一个租户消费平台共享组件
- 一个租户绑定自己的独享组件或外部凭据

### 3. `console.svc.plus`: 已实现能力

已实现的前端/BFF 语义：

- session user 结构已消费 `role / groups / permissions`
- 已预留 `tenantId / tenants`
- 已有基于 `permissions` 的通用访问控制工具：
  - `src/server/account/session.ts`
  - `src/lib/accessControl.ts`
- 已有多类服务端集成 token 解析逻辑：
  - OpenClaw
  - Vault
  - APISIX AI gateway
- Stripe 采用“前端只拿 `price_id`，secret 留在后端”模式

### 4. `console.svc.plus`: 预留能力与真实能力错位

`console.svc.plus` 已经按以下形状消费 session：

- `tenantId`
- `tenants`
- `permissions`
- `readOnly`

但 `accounts.svc.plus` 当前没有真实租户表或 membership 表支撑这些字段。

审计结论：

- `permissions` 是真实存在的。
- `tenantId / tenants` 属于接口形状预留，不是完整落地能力。
- 这会导致前端“看起来支持多租户”，但后端没有稳定的租户授权来源。

## Token Inventory

| Token / Secret Class | Current Owner | Current Scope | Current Visibility | Current Use | Risk |
| --- | --- | --- | --- | --- | --- |
| `xc_session` | `accounts.svc.plus` | user | user + BFF | 登录态、默认鉴权 | Medium |
| JWT `access_token` | `accounts.svc.plus` | user | user + BFF | 可选 JWT 鉴权 | Medium |
| JWT `refresh_token` | `accounts.svc.plus` | user | user/client | 刷新 access token | Medium |
| OAuth `exchange_code` | `accounts.svc.plus` | platform login handoff | frontend redirect only | 一次性换取真实 session token | Medium |
| `INTERNAL_SERVICE_TOKEN` | platform ops | platform service-to-service | backend only | 内部服务调用 | Medium |
| `OPENCLAW_GATEWAY_TOKEN` | platform or operator | integration/platform | server-side | OpenClaw gateway bridge | Medium |
| `VAULT_TOKEN` | platform or operator | integration/platform | server-side | Vault probe / defaults / token read | High |
| `AI_GATEWAY_ACCESS_TOKEN` | platform or operator | integration/platform | server-side | APISIX probe / gateway access | Medium |
| OAuth client secret | platform ops | integration/platform | backend only | GitHub / Google OAuth | High |
| Stripe secret | `accounts.svc.plus` backend | billing/platform | backend only | Checkout / portal / webhook | High |

## Integration Readiness Matrix

| Integration | Current Support | Shared Mode Today | Dedicated Mode Today | Notes |
| --- | --- | --- | --- | --- |
| GitHub OAuth | Implemented in `accounts` | No | No | Login only, not tenant-scoped |
| Google OAuth | Implemented in `accounts` | No | No | Login only, not tenant-scoped |
| Stripe Billing | Implemented through `accounts` + `console` | Partial | No | Subscription is user-bound, not tenant-bound |
| OpenClaw gateway | Implemented in `console` integration layer | Partial | Partial | Token can come from env/request/vault, but no tenant ownership model |
| Vault | Implemented in `console` integration layer | Partial | Partial | Can read token from env/request/vault, but no RBAC ownership boundary |
| APISIX AI gateway | Implemented in `console` integration layer | Partial | Partial | Same as Vault/OpenClaw |
| `INTERNAL_SERVICE_TOKEN` components | Implemented | Yes | No | Platform-internal only; no tenant isolation |

## High-Risk Findings

## P0 Follow-Up Implemented

已在 `2026-03-17` 完成的 P0 收口：

- `accounts.svc.plus` OAuth callback 不再向前端返回 `public_token + userId + email + role`
- `accounts.svc.plus/api/api.go` 改为签发短时、一次性 `exchange_code`
- `console.svc.plus` 只允许把 `exchange_code` 回传给 `POST /api/auth/token/exchange`
- `token/exchange` 现在只返回真实会话 token，不再接受调用方自报身份
- `console` 的主要用户管理 BFF 已对齐到 permission-aware gate

## High-Risk Findings

### 1. 前端多租户语义已存在，后端租户模型未落地

风险：

- 用户态 session 结构和真实数据模型不一致。
- 容易在后续接入共享模式/独享模式时，出现“前端可见 tenant，上游实际仍是全局 token”的越权设计。

### 2. `console` 管理路由已基本收口到 permission-aware gate，但 tenant-aware authorization 仍未存在

已对齐的例子：

- `src/app/api/admin/settings/route.ts`
- `src/app/api/admin/blacklist/route.ts`
- `src/app/api/admin/users/[userId]/role/route.ts`
- `src/app/api/admin/users/[userId]/pause/route.ts`
- `src/app/api/admin/users/[userId]/resume/route.ts`
- `src/app/api/admin/users/[userId]/renew-uuid/route.ts`

风险：

- 当前仍然只是在“全局角色/全局权限”模型上做最小权限判断。
- tenant 归属、tenant 角色和组件授权还没有真正进入访问控制链。

### 3. 公共服务组件 token 目前没有统一 owner/scope/visibility 治理

例如：

- `INTERNAL_SERVICE_TOKEN`
- `OPENCLAW_GATEWAY_TOKEN`
- `VAULT_TOKEN`
- `AI_GATEWAY_ACCESS_TOKEN`

当前更多依赖环境变量和运行时约定，而不是统一的“平台级 / 租户级 / 组件级”归属模型。

## Audit Conclusion

当前系统最准确的定位是：

- 已有可运行的全局 RBAC
- 已有前端 permission-aware 和 tenant-aware 抽象
- 但尚未形成真正一致的多租户 + tenant-scoped RBAC + token ownership 模型

因此后续改造不能只补 UI，也不能只补 schema。必须同时收口：

1. token 信任边界
2. `console` BFF 权限门禁
3. `accounts` 的 tenant 数据模型
4. 外部集成的 ownership / visibility / rotation 规则
