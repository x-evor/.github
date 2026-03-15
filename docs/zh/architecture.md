# 架构

该仓库是跨仓库治理、架构基线、发布规范与执行清单的控制平面。

本页作为系统边界、核心组件与仓库职责的双语总览入口。

## 与当前代码对齐的说明

- 文档目标仓库: `github-org-cloud-neutral-toolkit`
- 仓库类型: `control`
- 构建与运行依据: repository structure and scripts only
- 主要实现与运维目录: `cmd/`, `deploy/`, `ansible/`, `scripts/`, `test/`, `config/`
- `package.json` 脚本快照: No package.json scripts were detected.

## 需要继续归并的现有文档

- `architecture/project-overview.md`
- `architecture/rbac-plan-quota-architecture.md`

## 本页下一步应补充的内容

- 先描述当前已落地实现，再补充未来规划，避免只写愿景不写现状。
- 术语需要与仓库根 README、构建清单和实际目录保持一致。
- 将上方列出的历史 runbook、spec、子系统说明逐步链接并归并到本页。
- 随着目录结构、服务关系和集成依赖变化，持续同步图示与职责说明。
