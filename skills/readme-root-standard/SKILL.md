# Skill: readme-root-standard

## Purpose

Standardize repository root `README.md` across Cloud-Neutral Toolkit repos.

Goals:
- Consistent structure so users can scan quickly (what it is, how to run, how to deploy, where docs are).
- Bilingual support: ZH + EN in one file by default.
- Clear deployment requirements and security posture.
- Works for multiple repo types: runtime services, web apps, infra repos, libraries, control-plane repos.

Non-goals:
- Do not duplicate full docs; README should link out to `docs/`.
- Do not embed secrets or real tokens.

## Rules

1. README must be present at repo root: `README.md`.
2. Bilingual format: ZH first, EN second (or side-by-side blocks), keep section headings mirrored.
3. First screen (top ~60 lines) should answer:
   - What this repo is (one sentence)
   - Who should use it (audience)
   - How to start (one command)
   - Where docs live
4. Setup script convention (optional but recommended):
   - Provide a `scripts/setup.sh` that supports `curl | bash`.
   - Use cache-bust query: `?$(date +%s)`.
   - Script must be safe: no secrets written; no destructive actions; print next steps.
5. Security:
   - Never commit real credentials. Only document secret *names* and where they live.
   - Follow `skills/env-secrets-governance/SKILL.md`.
6. Release/Versioning:
   - Services/libs: SemVer; tags: `<repo-name>-vX.Y.Z` (if applicable).

## Recommended README Structure (Template)

Use this structure unless the repo is purely internal:

1. Title + one-line description
2. ZH/EN short description block
3. Key features (bullets or short table)
4. Deployment requirements (table)
5. Quickstart
6. Deployment modes (VM/Docker Compose/Kubernetes/Helm/Cloud Run/Vercel, as applicable)
7. CI/CD automation (what workflows exist)
8. Tech stack / dependencies
9. Docs index (links to `docs/` paths)
10. Security & secrets (names only)
11. License
12. Contributing
13. Support / Contacts

## Template Snippets

### Header (ZH/EN)

```md
# <repo-name>

<一句话中文简介。>

> <One-line English description.>
```

### Requirements Table

```md
## 部署要求 (Deployment Requirements)

| 维度 | 要求 / 规格 | 说明 |
|---|---|---|
| 网络 | 公网 IP + 域名 (DNS) | 域名需解析至主机 IP (用于 ACME 证书) |
| 端口 | 80, 443 | 80 用于证书验证 (HTTP-01)，443 为 TLS 入口 |
| 最低 | 1 CPU / 2GB RAM / 20GB SSD | 仅支持基础功能 |
| 推荐 | 2 CPU / 4GB RAM / 50GB SSD | 支持高并发/全量扩展 |
```

### Quickstart (curl | bash)

```md
## 快速开始 (Quickstart)

### 一键安装 (Setup Script)

```bash
curl -fsSL "https://raw.githubusercontent.com/cloud-neutral-toolkit/<repo-name>/main/scripts/setup.sh?$(date +%s)" | bash -s -- <repo-name>
```
```

Notes:
- If the repo is private, document the prerequisites (e.g. `gh auth login`).
- If the script accepts parameters, document them as `bash -s -- <arg1> <arg2>`.

### Secrets Names Only

```md
## 安全与密钥 (Security & Secrets)

This project uses secrets; do not commit real values.

Common secrets (names only):
- `CLOUDFLARE_API_TOKEN`: DNS apply (cloudflare)
- `ALIYUN_AK`, `ALIYUN_SK`: DNS apply (alicloud)
- `GCP_*`: IAC/Deploy (prefer OIDC Workload Identity Federation)
- `VERCEL_TOKEN`: optional Vercel API operations
```

## Repo-Type Guidance

### Runtime Service Repos (example: `postgresql.svc.plus`)

Add:
- "Extensions / capabilities" section
- Deployment modes
- Ops docs links (backup/monitoring)
- Security model (TLS entry, auth)

### Web App Repos (example: `console.svc.plus`)

Add:
- Local dev steps (`yarn dev`)
- Configuration pointers (`.env.example`)
- Vercel preview/deploy notes (if used)

### GitOps / Infra Repos

Add:
- Repo layout summary
- Environments and apply order
- Safety gates + rollback notes

## Checklist (PR Review)

- README has ZH + EN
- Quickstart is copy/paste-able
- Docs links exist and are valid
- No secrets or real tokens in repo
- Setup script is non-destructive and prints next steps

