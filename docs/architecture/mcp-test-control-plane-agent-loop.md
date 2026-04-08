# MCP Test Control Plane Agent Loop

## Design Goals

All control-plane behavior must remain:

- schedulable
- composable
- observable
- auto-remediable

## Agent Loop Policy

The gateway and CLI run with `agent_loop=true` by default.

When a test run fails:

1. The gateway inspects failed MCP tasks.
2. It generates structured fix suggestions.
3. It emits those suggestions in the final JSON result.
4. CI keeps the workflow red, which blocks merge until the next run passes.

When a new feature is supplied with `feature_name` or `feature_notes`:

1. The gateway generates unit-test drafts.
2. The gateway generates integration-test drafts.
3. The gateway generates e2e-test drafts.
4. These drafts are returned in the JSON report so an Agent can turn them into real tests in the next loop step.

When a PR is created:

1. The PR workflow runs the unified CLI.
2. The CLI calls the gateway.
3. The gateway expands the event into a multi-MCP plan.
4. The workflow fails on any non-success result.

## Merge Gate

- PR merge is forbidden while the PR workflow is red.
- Release load testing is blocked unless release e2e passes first.
- Critical-path failures stop dependent tasks immediately.
