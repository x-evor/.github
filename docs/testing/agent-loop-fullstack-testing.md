# Agent Loop Full-Stack Testing

## Goal

Use the control repo as the single test control plane for:

- `xworkmate.svc.plus` Flutter Desktop
- `accounts.svc.plus` Go API
- `github-org-cloud-neutral-toolkit` CI orchestration and merge gates

This layer is intentionally non-invasive:

- do not change business semantics
- add tests, fixtures, metadata, CI hooks, and generated drafts only

## Required Artifacts

Every agent-loop run writes these JSON artifacts:

- `run-result.json`
- `generated-tests.json`
- `fix-suggestions.json`
- `task-timeline.json`

These are uploaded in GitHub Actions and serve as merge-gate evidence.

## Required PR Checks

Configure these required checks on protected branches:

- `agent-loop / quick-stack`
- `agent-loop / critical-path`
- `agent-loop / desktop-e2e`

Merge must stay blocked until all three are green.

## Event Contract

`test.run` supports these planning fields:

- `feature_id`
- `feature_name`
- `feature_notes`
- `repo_scope`
- `pr_number`
- `event_source`

Recommended defaults:

- `repo_scope=xworkmate.svc.plus,accounts.svc.plus,github-org-cloud-neutral-toolkit`
- `event_source=pr` for pull requests
- `event_source=release` for release validation

## Layer Mapping

### Flutter Desktop

- `flutter-widget-mcp`
- `flutter-golden-mcp`
- `flutter-integration-mcp`
- `flutter-patrol-mcp`
- `desktop-e2e-mcp`

### Go API

- `go-unit-mcp`
- `api-contract-mcp`

### Control Plane

- `test-gen-mcp`
- `fix-suggest-mcp`

## Failure Policy

- `go-unit-mcp`
- `api-contract-mcp`
- `flutter-integration-mcp`
- `desktop-e2e-mcp`

are critical-path tasks.

If any of them fails, dependent tasks must be skipped and the workflow must fail.

## Business Repo Templates

Use these templates when wiring sibling repos:

- [xworkmate test matrix](/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/templates/testing/xworkmate/README.md)
- [accounts test matrix](/Users/shenlan/workspaces/cloud-neutral-toolkit/github-org-cloud-neutral-toolkit/templates/testing/accounts/README.md)
