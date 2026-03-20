# svc-ai-gateway Models

## External model contract

External model names should match the upstream model names exposed to clients.

Current models:

- `z-ai/glm5`
- `moonshotai/kimi-k2.5`
- `minimaxai/minimax-m2.5`
- `text-embedding-3-small`

## Model mapping

| Public model | Endpoint | Gateway plugin | Upstream model source |
| :----------- | :------- | :------------- | :-------------------- |
| `z-ai/glm5` | `/v1/chat/completions` | `ai-proxy-multi` | `OLLAMA_CHAT_MODEL` (`glm-5:cloud`) and `NVIDIA_CHAT_MODEL` (`z-ai/glm5`) |
| `moonshotai/kimi-k2.5` | `/v1/chat/completions` | `ai-proxy` | `OLLAMA_KIMI_MODEL` (`kimi-k2.5:cloud`) |
| `minimaxai/minimax-m2.5` | `/v1/chat/completions` | `ai-proxy` | `OLLAMA_MINIMAX_MODEL` (`minimax-m2.5:cloud`) |
| `text-embedding-3-small` | `/v1/embeddings` | `ai-proxy` | `EMBEDDINGS_MODEL` |

## Why expose upstream names directly

- clients only talk to `api.svc.plus`
- the request `model` stays identical to the upstream contract
- provider fallback for the same model can still stay in the gateway
- you avoid maintaining a second alias namespace
