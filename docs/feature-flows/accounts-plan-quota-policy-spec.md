# accounts.svc.plus 套餐与权限策略特性说明

## 范围

本特性定义账号服务在以下场景的统一策略：

- 角色鉴权（RBAC）
- 套餐能力下发（Plan Entitlements）
- 配额校验（Quota）
- 邀请续期与升级链路

## 角色策略（RBAC）

- `admin`：全权限。
- `operator`：运营权限，具体能力由 `role_permissions` 和权限矩阵决定。
- `user`：普通用户权限。
- `readonly`：只读权限，禁止任何写操作、禁止改密。

## 套餐策略（Plan）

### seed_top100
- 永久免费基础功能。
- 共享加速 UUID。
- 默认开放 beta 特性。

### trial
- 注册 1 个月免费。
- 到期且未续费：自动 rotate UUID。

### cloud_shared
- 价格：$1.9。
- 共享加速服务。
- 共享 AI 助手每日 5 次。

### basic
- 价格：$9.9。
- 共享 AI 助手网关。
- 次数不限（可叠加全局防滥用限流）。

### pro
- 价格：$19.9。
- 专属加速节点。
- 专属 AI 助手网关。

## 配额策略（Quota）

- 计量粒度：`(user_id, feature_key, date)`。
- 默认策略：
  - `cloud_shared.ai_daily_limit = 5`
  - `basic/pro.ai_daily_limit = unlimited`

## 邀请续期

- 条件：被邀请用户为“新注册并首次开通目标套餐”。
- 奖励：邀请者当前套餐 `expires_at + 1 month`。
- 规则：续期不改 UUID。
- 反作弊：设备/IP/支付指纹去重，奖励延迟 24h 生效。

## 升级策略

- 允许原地升级：`trial -> cloud_shared -> basic -> pro`。
- 升级时保留 UUID。
- 权益即时生效，支持按剩余时长折算（proration）。
