# svc-ai-gateway Providers

## Plugin choice

- `ai-proxy`
  Use for one fixed upstream provider per public model.
- `ai-proxy-multi`
  Use for ordered fallback, retries, and multi-provider policy.

## Current upstream env contract

| Public model group | Required env |
| :----------------- | :----------- |
| Ollama Cloud GLM chat | `OLLAMA_API_KEY`, `OLLAMA_CHAT_ENDPOINT`, `OLLAMA_CHAT_MODEL` |
| Ollama Cloud Kimi chat | `OLLAMA_API_KEY`, `OLLAMA_CHAT_ENDPOINT`, `OLLAMA_KIMI_MODEL` |
| Ollama Cloud MiniMax chat | `OLLAMA_API_KEY`, `OLLAMA_CHAT_ENDPOINT`, `OLLAMA_MINIMAX_MODEL` |
| NVIDIA Cloud GLM chat | `NVIDIA_API_KEY`, `NVIDIA_CHAT_ENDPOINT`, `NVIDIA_CHAT_MODEL` |
| Embeddings | `EMBEDDINGS_API_KEY`, `EMBEDDINGS_ENDPOINT`, `EMBEDDINGS_MODEL` |

## Fallback route

`z-ai/glm5` uses `ai-proxy-multi` with this order:

1. Ollama Cloud (`glm-5:cloud`)
2. NVIDIA Cloud (`z-ai/glm5`)

Only the Ollama Cloud provider requires model-name mapping on this route:

- public model: `z-ai/glm5`
- Ollama upstream model: `glm-5:cloud`
- NVIDIA upstream model: `z-ai/glm5`

Fallback is triggered on:

- `429`
- `5xx`
- provider rate-limiting signals

## Secret handling

This repository keeps only placeholder values in `.env`.

For production:

- keep real `AI_GATEWAY_ACCESS_TOKEN`, `OLLAMA_API_KEY`, and `NVIDIA_API_KEY` in the repository root `.env` or your secret manager
- render `.env` from your secret manager
- reload APISIX after rotating credentials
- keep provider credentials out of client-side configs
