# svc-ai-gateway API

`svc-ai-gateway` is the OpenAI-compatible front door for upstream model access.

## Public entrypoint

- Base URL: `https://api.svc.plus`

## Authentication

- All public endpoints require `Authorization: Bearer <AI_GATEWAY_ACCESS_TOKEN>`.
- TLS terminates at Caddy.
- APISIX enforces gateway auth and strips the client credential before proxying upstream.

## Endpoints

- `POST /v1/chat/completions`
- `POST /v1/embeddings`
- `GET /v1/models`

## Deployment mode

- APISIX standalone mode
- YAML file-driven config
- no etcd
- no dashboard
- config stored in Git under `conf/`
- Caddy runs on the host as the public TLS entrypoint and reverse proxies to `127.0.0.1:9080`
- APISIX validates `Authorization` with `key-auth` and then routes to the configured provider

## Current route model

- `POST /v1/chat/completions`
  Route selection is based on `post_arg.model`.
- `POST /v1/embeddings`
  Route selection is based on `post_arg.model`.
- `GET /v1/models`
  Returns a static gateway-maintained model catalog.

## Supported chat models

- `z-ai/glm5`
- `moonshotai/kimi-k2.5`
- `minimaxai/minimax-m2.5`

## Supported embedding models

- `text-embedding-3-small`

## Important limitation

This YAML-only version maps public model names to providers by APISIX route matching on request-body fields. It works for a fixed model catalog, but it is not yet a full dynamic model registry. If you want arbitrary models loaded from a database or dynamic policy engine, add a thin adapter service or a custom APISIX plugin later.

## Example

```bash
curl https://api.svc.plus/v1/models \
  -H "Authorization: Bearer ${AI_GATEWAY_ACCESS_TOKEN}"
```

## Run

```bash
cd svc-ai-gateway
docker compose up -d
```

## Validate

```bash
cd svc-ai-gateway
./scripts/validate.sh
```

## Reload

```bash
cd svc-ai-gateway
./scripts/reload.sh
```
