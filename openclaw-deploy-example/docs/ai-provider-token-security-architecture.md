# AI Provider Token 安全设计（单域名 `.svc.plus`）

目标：解决 AI Provider 的 `AS/SK`、`API Key` 散落在 `.env`、脚本、网关配置中的问题，改为 **Vault 中心化托管 + 网关本地优先/公网回落**。

固定本地端口：
- Vault: `8200`
- APISIX: `9080`
- Ollama: `11434`
- OpenClaw Gateway: `18789`

---

## 1) 设计原则

- 密钥只在 Vault 保存，业务配置不再直接保存明文 `AS/SK`。
- APISIX/OpenClaw 仅持有短期身份凭证（JWT/AppRole），不持有长期 Provider Secret。
- 对外调用统一通过 `ai.svc.plus`，本地优先，本地不可用时回落公网上游。
- 对第三方 Provider 的签名在受控组件内完成，尽量避免把 `SK` 暴露给网关插件层。

---

## 2) 部署架构图（安全域 + 数据流）

```mermaid
flowchart LR
    subgraph Client["Client / SDK"]
      U1["开发者工具 / App"]
    end

    subgraph Edge["单域名入口 ai.svc.plus (本地优先, fallback 公网)"]
      CADDY["Caddy TLS Edge :8443"]
      APISIX["APISIX :9080"]
    end

    subgraph LocalCtrl["本地控制面"]
      OCG["OpenClaw Gateway :18789"]
      VAULT["Vault :8200"]
      BROKER["Secret Broker / Signer"]
      OLLAMA["Ollama :11434"]
    end

    subgraph External["公网 AI Provider"]
      P1["NVIDIA / Moonshot / Minimax / OpenAI API"]
    end

    U1 -->|"HTTPS /v1/*"| CADDY
    CADDY --> APISIX
    APISIX -->|"local LLM"| OLLAMA
    APISIX -->|"provider request (no long-lived secret)"| BROKER
    BROKER -->|"read secret / sign request"| VAULT
    BROKER -->|"signed upstream call"| P1
    APISIX -.fallback.->|"if local path unavailable"| P1
    OCG -->|"machine identity / policy bootstrap"| VAULT
```

---

## 3) 核心安全方案（解决 Token 散落）

### A. 秘钥分层

- **L0 长期密钥（仅 Vault）**
  - `kv/ai/providers/<provider>/access_key`
  - `kv/ai/providers/<provider>/secret_key`
  - 访问策略：仅 `secret-broker` 角色可读。
- **L1 运行时短期凭证（给 APISIX / OpenClaw）**
  - 通过 JWT/AppRole 获取，TTL 建议 `15m~1h`，可续租。
  - 仅可调用 Broker，不可直接读 Provider 明文密钥。
- **L2 请求级签名**
  - 每次调用由 Broker 使用 Vault 中密钥签名，返回已签名请求或短期 token。

### B. 网关最小暴露面

- APISIX 配置里移除第三方 Provider 明文 `API_KEY`/`SK`。
- APISIX 仅配置：
  - Broker 地址
  - Broker 认证方式（mTLS/JWT）
  - 允许调用的 provider/model 白名单

### C. 审计与轮转

- Vault audit device 开启，记录谁在何时访问了哪类 secret。
- Provider 密钥轮转在 Vault 内完成，Broker 无状态热更新。
- 回滚策略：按版本化 secret path（例如 `kv/ai/providers/nvidia/v2`）。

---

## 4) 单域名运行策略（你当前架构）

- `ai.svc.plus`:
  - 优先：`APISIX :9080`（本地）
  - 回落：公网 `api.svc.plus` 或指定云网关
- `vault.svc.plus`:
  - 优先：`Vault :8200`（本地）
  - 回落：公网 Vault（可选）
- `openclaw.svc.plus`:
  - 保持现状：本地 `:18789` 为主

---

## 5) 推荐落地步骤（按风险递减）

1. 把现有 Provider `AS/SK` 全量迁入 Vault（按 provider 独立 path）。
2. 新增 `secret-broker`（本地进程），实现：
   - 从 Vault 读密钥
   - 代签名/代发起上游请求
   - 返回标准 OpenAI 兼容响应给 APISIX
3. APISIX 路由改为仅调用本地 Broker，不再直接使用 provider key。
4. 删除 `.env` 中第三方 Provider 长期密钥，仅保留 Vault 访问身份配置。
5. 启用 Vault 审计与密钥轮转计划（按月/按季度）。

---

## 6) 最小化配置清单（示意）

- `VAULT_ADDR=http://127.0.0.1:8200`
- `SECRET_BROKER_ADDR=http://127.0.0.1:<broker-port>`
- `APISIX_UPSTREAM_LOCAL=http://127.0.0.1:9080`
- `OLLAMA_ADDR=http://127.0.0.1:11434`
- `OPENCLAW_GATEWAY_ADDR=http://127.0.0.1:18789`

注意：不再在 APISIX/OpenClaw 的 `.env` 中保留第三方 Provider 长期 `AS/SK`。
