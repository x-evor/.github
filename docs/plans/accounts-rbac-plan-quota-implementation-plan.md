# accounts.svc.plus RBAC + 套餐 + 配额实施计划

## Phase 1：数据模型与约束

- [ ] 建表：`roles / permissions / role_permissions`
- [ ] 建表：`plans / user_plan_subscriptions / user_entitlements`
- [ ] 建表：`quota_usage_daily / invites / invite_rewards / uuid_rotation_events`
- [ ] 初始化角色与权限、套餐与默认配额

## Phase 2：策略引擎落地

- [ ] 鉴权层：Role + permission_key 校验
- [ ] 权益层：按 `plan` 展开 entitlements
- [ ] 配额层：按日计量与拦截
- [ ] 审计层：记录升级/续期/邀请/UUID 轮换事件

## Phase 3：业务规则落地

- [ ] trial 到期自动 rotate UUID
- [ ] 续费与邀请续期保持 UUID 不变
- [ ] 升级链路（trial -> cloud_shared -> basic -> pro）
- [ ] 升级权益即时生效 + proration

## Phase 4：风控与运营

- [ ] 邀请反作弊（首购判定、设备/IP/支付指纹去重）
- [ ] 奖励延迟发放（默认 24h）
- [ ] 运营权限矩阵可配置

## 验收清单

- [ ] 角色隔离正确（readonly 无写权限）
- [ ] cloud_shared 每日 5 次 AI 配额生效
- [ ] basic/pro 不限次且受全局限流保护
- [ ] trial 到期 UUID 自动轮换
- [ ] 邀请续期成功且 UUID 保持不变
- [ ] 升级链路可原地执行，无需迁移账号
