# 部署

该仓库是跨仓库治理、架构基线、发布规范与执行清单的控制平面。

本页用于统一部署前提、支持的拓扑、运维检查项与回滚注意事项。

## 与当前代码对齐的说明

- 文档目标仓库: `github-org-cloud-neutral-toolkit`
- 仓库类型: `control`
- 构建与运行依据: repository structure and scripts only
- 主要实现与运维目录: `cmd/`, `deploy/`, `ansible/`, `scripts/`, `test/`, `config/`
- `package.json` 脚本快照: No package.json scripts were detected.

## 需要继续归并的现有文档

- `Runbook/Fix-Agent-404-And-UUID-Change.md`
- `Runbook/Fix-CloudRun-Stunnel-Startup-Failure.md`
- `Runbook/Fix-Rotating-UUID-Sync-Archive-2026-02-06.md`
- `Runbook/Migrate-CloudRun-Core-To-DockerCompose-2C2G.md`
- `Runbook/Migrate-CloudRun-Core-To-SingleNode-K3s-2C4G.md`
- `Runbook/README.md`
- `Runbook/Security-Scrubbing-Archive-2026-02-06.md`
- `Runbook/Setup-Sandbox-Mode-and-Agent-Sync.md`

## 本页下一步应补充的内容

- 先描述当前已落地实现，再补充未来规划，避免只写愿景不写现状。
- 术语需要与仓库根 README、构建清单和实际目录保持一致。
- 将上方列出的历史 runbook、spec、子系统说明逐步链接并归并到本页。
- 每次发布前，依据当前脚本、清单、CI/CD 流程和环境契约重新核对部署步骤。
