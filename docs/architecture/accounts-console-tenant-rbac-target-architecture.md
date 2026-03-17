# Accounts + Console 多租户 RBAC 与 Token 目标架构

## Summary

目标架构统一解决 4 个问题：

1. `accounts.svc.plus` 从“全局用户 RBAC”演进到“平台级 + 租户级双层授权”
2. `console.svc.plus` 从“预留 tenant 语义”演进到“真正 tenant-aware access control”
3. 公共组件与外部集成同时支持共享模式和独享模式
4. token 从“环境变量拼装”演进到“owner / scope / visibility / rotation 可治理”

默认采用双层 token 模型：

- 平台级公共 token
- 租户级 / 组件级 / 用户级 token

## Target Operating Modes

### 1. 共享模式

定义：

- 平台维护一个共享组件或共享外部集成
- 租户通过授权消费该能力
- 普通用户不会直接接触平台级 token

适用场景：

- 平台统一 OpenClaw gateway
- 平台统一 APISIX AI gateway
- 平台统一 Vault 代理能力
- 平台内部公共服务组件

规则：

- 共享资源必须仍然带 tenant 上下文
- 平台级 token 仅 `root / platform_admin` 可见、可轮换、可修复
- 租户只拿到被裁剪后的组件能力和使用权限

### 2. 独享模式

定义：

- 某个 tenant 自己绑定外部集成凭据、专属实例或专属组件
- 配置、token、审计和权限完全归属该 tenant

适用场景：

- tenant 自己的 Vault
- tenant 自己的 APISIX / AI gateway
- tenant 自己的 OpenClaw gateway
- tenant 自己的 billing/integration connector

规则：

- token 归属 tenant 或 dedicated component
- 非平台管理员不可查看其他 tenant 的 dedicated credential
- tenant_owner / tenant_admin 负责租户内可见性与轮换

## Target RBAC Model

### 1. 主体层级

平台级主体：

- `root`
- `platform_admin`
- `platform_operator`

租户级主体：

- `tenant_owner`
- `tenant_admin`
- `tenant_operator`
- `tenant_member`
- `tenant_viewer`

### 2. 核心实体

- `tenant`
- `tenant_membership`
- `tenant_role_binding`
- `service_component`
- `service_component_credential`
- `token_scope`

建议语义：

- `tenant`
  - 平台上的组织/工作空间/业务隔离单元
- `tenant_membership`
  - 用户加入哪些 tenant
- `tenant_role_binding`
  - 用户在该 tenant 内扮演什么角色
- `service_component`
  - 一个可授权的公共或独享服务组件
- `service_component_credential`
  - 组件使用的 token/secret 的元数据与归属，不直接把 secret 写入业务表
- `token_scope`
  - `platform / tenant / component / user`

### 3. 权限判定顺序

所有写入目标设计与后续实现，统一按以下顺序判定：

1. 平台级硬限制
2. tenant 归属
3. tenant 角色 / tenant 权限
4. 组件级授权

不得跳过 tenant 归属直接用平台角色放行 tenant 操作。

## Token Architecture

### 1. 平台级公共 Token

适用：

- `INTERNAL_SERVICE_TOKEN`
- 平台统一 OpenClaw / Vault / APISIX 共享组件 token
- OAuth client secret
- Stripe platform secret

规则：

- 默认仅 `root / platform_admin` 可见
- `platform_operator` 可用但默认不可见原文
- 普通租户用户永远不能直接查看原文
- 只允许通过授权后的平台组件能力消费

### 2. 租户级 Token

适用：

- tenant 绑定的共享组件访问令牌
- tenant 自己的集成配置入口

规则：

- 归属单个 tenant
- `tenant_owner / tenant_admin` 可管理
- `tenant_operator` 可按 policy 使用
- 普通成员按组件授权使用，不默认可见原文

### 3. 组件级 Token

适用：

- 某个 shared/dedicated component 自己持有的运行 token

规则：

- token 必须挂到 component ownership 上
- 组件可以属于平台，也可以属于 tenant
- 组件 token visibility 取决于 owner + scope

### 4. 用户级 Token

适用：

- 终端用户个人 API token
- 需要代表个人身份的 access token

规则：

- 不能替代平台或 tenant token
- 必须能审计创建者、tenant、组件范围和过期时间

## API Token Target Changes

### 1. `exchange_code -> token/exchange`

目标结论：

- 已执行的 P0 方案是：OAuth callback 只签发后端生成、一次性消费的 `exchange_code`
- 不再保留“调用方自报 `user_id/email/roles`”模式

允许的未来方向仅二选一：

- 保留当前 `exchange_code -> real session token` 方案，并继续限制为单次消费、短 TTL
- 如果后续控制面统一跨域 cookie，可直接废弃该入口

默认方案：

- 维持一次性 `exchange_code` 交接
- 不再作为终端用户“自报身份换令牌”的入口

### 2. `INTERNAL_SERVICE_TOKEN`

目标结论：

- 保留，但重新定义为平台级服务间 token
- 只用于 platform internal component 调用
- 不承载终端用户身份
- 不能代替 tenant-scoped authorization

### 3. `console` BFF Gate

目标结论：

- 统一改成 permission-aware gate
- 角色判断只能作为默认兜底，不再作为唯一授权条件
- 对 tenant 操作必须增加 tenant-scoped authorization

## Shared / Dedicated Integration Matrix

| Integration | Current Mode | Target Shared Mode | Target Dedicated Mode | Required Change |
| --- | --- | --- | --- | --- |
| GitHub OAuth | platform login | No | No | 仅保留身份登录，不建共享/独享组件 |
| Google OAuth | platform login | No | No | 同上 |
| Stripe billing | platform billing | Optional | Optional | 从 user-bound 扩展到 tenant/account ownership |
| OpenClaw gateway | mixed env/request/vault | Yes | Yes | 增加 component ownership、tenant scope、token visibility |
| Vault | mixed env/request/vault | Yes | Yes | 增加 platform shared vault connector 与 tenant-owned vault connector |
| APISIX AI gateway | mixed env/request/vault | Yes | Yes | 增加 component credential registry 与 RBAC gate |
| `INTERNAL_SERVICE_TOKEN` component | platform internal | Yes | No | 明确仅平台内部使用 |

## Recommended Phase Plan

### P0

- 移除 `public_token` 自报身份链路，固化一次性 `exchange_code -> token/exchange`
- 统一 `console` BFF 的 permission gate
- 定义平台级公共 token 可见性规则

### P1

- 对齐 session contract 与真实数据模型
- 明确 `tenantId / tenants` 的来源与缺省行为
- 建立 integration registry 与 token ownership matrix

### P2

- 在 `accounts` 引入 `tenant / tenant_membership / tenant_role_binding`
- 在 `console` 全量切换到 tenant-aware access control

### P3

- 支持 shared / dedicated 组件并存
- 建立组件授权、凭据归属、轮换和审计链路

## Defaults For Implementers

后续实施时不再需要自行决定以下事项：

- 平台级公共 token 默认不可被普通用户查看
- tenant 级授权永远晚于平台级硬限制，但早于组件使用判定
- `INTERNAL_SERVICE_TOKEN` 不表示终端用户身份
- OAuth 登录交接只允许一次性 `exchange_code`
- shared component 与 dedicated component 必须用 owner + scope 明确归属

## Acceptance Criteria

当后续实施完成时，应满足：

- `accounts` 能表达一个用户属于多个 tenant
- `console` session 的 `tenantId / tenants / permissions` 有真实后端来源
- `console` 管理 BFF 不再只看角色
- 平台级公共 token 与 tenant 级 token 有明确可见性和归属
- 外部集成能够明确区分 shared mode 与 dedicated mode
