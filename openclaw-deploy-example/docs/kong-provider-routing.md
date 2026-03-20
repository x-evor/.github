# Kong Provider Routing Template（已由 svc-ai-gateway 替代）

旧的 `deploy/kong/kong-providers.yaml` 设计已被 `svc-ai-gateway/` 替代。

现在请看：

- [svc-ai-gateway API](../svc-ai-gateway/docs/api.md)
- [svc-ai-gateway Models](../svc-ai-gateway/docs/models.md)
- [svc-ai-gateway Providers](../svc-ai-gateway/docs/providers.md)

新的前门是标准 OpenAI-compatible 入口：

- `https://api.svc.plus/v1/chat/completions`
- `https://api.svc.plus/v1/embeddings`
- `https://api.svc.plus/v1/models`
