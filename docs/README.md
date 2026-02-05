# Documentation Index

Docs are organized by engineering lifecycle domains.

## Architecture

- `architecture/project-overview.md`: multi-repo architecture, ownership, topology, and operating model.
- `architecture/rbac-plan-quota-architecture.md`: role/plan/quota 三层权限与套餐总体架构。

## Design & Development

- `design-development/service-chain-auth-implementation.md`: service chain auth implementation design and execution playbook.

## Feature Flows

- `feature-flows/vless-qr-code-flow.md`: VLESS QR code functional flow.
- `feature-flows/accounts-plan-quota-policy-spec.md`: accounts 套餐能力、配额、邀请续期与升级策略说明。
- `feature-flows/accounts-oauth-binding-spec.md`: accounts social OAuth login/bind/unbind API and data model spec.
- `feature-flows/console-oauth-integration-spec.md`: console social OAuth login/bind UI and callback integration spec.

## Operations & Governance

- `operations-governance/governance.md`: branch, commit, PR, version, and release governance.
- `operations-governance/release-checklist.md`: release gates, sequence, and rollback order.
- `operations-governance/cross-repo-tasks.md`: cross-repo backlog and execution templates.
- `operations-governance/deployment-summary.md`: deployment summary and operational validation.
- `operations-governance/implementation-complete.md`: implementation completion and delivery report.
- `operations-governance/observability-monitoring-chain.md`: node -> vector -> ingest -> metrics/logs/traces monitoring chain.
- `operations-governance/db-migration-runbook.md`: PostgreSQL migration runbook (backup/restore, stop-write, online).

## Testing

- `testing/full-stack-test-plan.md`: full-stack test strategy and test plan.

## Security

- `security/shared-token-auth-design.md`: service token auth design.
- `security/internal-auth-usage.md`: internal auth usage guide.
- `security/service-chain-auth-audit.md`: service chain auth audit report.
- `security/security-audit-token-transmission.md`: token transmission security audit.

## Plans

- `plans/oauth-social-login-rollout.md`: phased rollout plan for GitHub/Google login and account binding.
- `plans/accounts-rbac-plan-quota-implementation-plan.md`: accounts RBAC + 套餐 + 配额实施计划。
- `plans/oauth2-integration-plan.md`: OAuth2 integration plan.
- `plans/management-page-plan.md`: management page delivery plan.
