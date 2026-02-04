# RBAC + Plan + Quota 总体架构设计

## 设计目标

- 统一权限模型：**Role 管操作权限，Plan 管产品能力，Quota 管用量限额**。
- 支持账号分层：root/admin/operator/user/readonly。
- 支持套餐升级与邀请续期，并可审计、可反作弊。

## 三层模型

### 1) Role（能不能做）

- `admin`：全权限（含高危操作）。
- `operator`：运营管理权限（默认不含高危操作，可配置）。
- `user`：普通订阅用户。
- `readonly`：只读体验用户（禁止写操作、禁止改密）。

### 2) Group/Plan（能用什么）

- `seed_top100`：永久免费基础功能、共享加速 UUID、开放 beta。
- `trial`：注册后 1 个月免费，到期未续费自动更换 UUID。
- `cloud_shared`（$1.9）：共享加速服务，AI 助手每日 5 次。
- `basic`（$9.9）：共享 AI 助手网关，不限次数。
- `pro`（$19.9）：专属加速节点、专属 AI 助手网关。

### 3) Quota（能用多少）

- 按 user/feature/day 记录用量。
- 核心配额：`cloud_shared.ai_daily_limit = 5`。
- `basic/pro` 可配置为 unlimited，同时保留全局防滥用限流。

## 核心策略

### UUID 策略

- `trial` 到期未续费：自动 rotate UUID。
- 付费续期/邀请续期：UUID 不变。

### 邀请续期策略

- 邀请者每成功邀请 1 个“新注册并开通目标套餐”用户：`expires_at +1 month`。
- 适用：`trial / cloud_shared / basic / pro`。
- `seed_top100` 默认只记积分（不续期）。

### 升级策略

- 支持原地升级：`trial -> cloud_shared -> basic -> pro`。
- 保留 UUID，不强制变更。
- 权益即时生效；费用按剩余时长折算（proration）。

## 反作弊建议

- 被邀请人必须满足首购/首开通。
- 设备/IP/支付指纹去重。
- 奖励发放延迟 24h（防退款套利）。

## 数据落库最小集合

- `roles`, `permissions`, `role_permissions`
- `plans`（价格、能力、配额、uuid_policy）
- `user_plan_subscriptions`（current_plan, expires_at, status）
- `user_entitlements`（展开后的能力快照）
- `quota_usage_daily`（按 user/feature/date）
- `invites`, `invite_rewards`
- `uuid_rotation_events`
