package scheduler

import (
	"fmt"
	"strings"

	"xcloudflow/internal/protocol"
)

const (
	PriorityCritical = "critical"
	PriorityNormal   = "normal"
)

type Input struct {
	GitEvent     string
	GitRef       string
	TestIntent   string
	ChangedAreas []string
	Env          string
	MCP          string
	MCPs         []string
	RunAll       bool
	Suite        string
	Retry        *protocol.Retry
}

var allMCPs = []string{
	"frontend-mcp",
	"nextjs-mcp",
	"chrome-mcp",
	"api-mcp",
	"db-mcp",
	"e2e-mcp",
	"load-mcp",
}

func BuildPlan(in Input) protocol.Plan {
	switch {
	case in.RunAll:
		return buildAllPlan(in)
	case in.MCP != "" || len(in.MCPs) > 0:
		return buildExplicitPlan(in)
	case isReleaseEvent(in):
		return buildReleasePlan(in)
	case strings.EqualFold(in.GitEvent, "hotfix"):
		return buildHotfixPlan(in)
	default:
		return buildPRPlan(in)
	}
}

func buildAllPlan(in Input) protocol.Plan {
	steps := make([]protocol.PlanStep, 0, len(allMCPs))
	for i, mcp := range allMCPs {
		steps = append(steps, newStep(
			fmt.Sprintf("step-all-%d", i+1),
			mcp,
			defaultSuiteForMCP(mcp, in),
			PriorityNormal,
			"full-stack",
			nil,
			retryFor(PriorityNormal, in.Retry),
		))
	}
	return protocol.Plan{Plan: steps}
}

func buildExplicitPlan(in Input) protocol.Plan {
	targets := in.MCPs
	if in.MCP != "" {
		targets = append([]string{in.MCP}, targets...)
	}
	steps := make([]protocol.PlanStep, 0, len(targets))
	for idx, mcp := range targets {
		steps = append(steps, newStep(
			fmt.Sprintf("step-explicit-%d", idx+1),
			mcp,
			defaultSuiteForMCP(mcp, in),
			PriorityNormal,
			"explicit",
			nil,
			retryFor(PriorityNormal, in.Retry),
		))
	}
	return protocol.Plan{Plan: steps}
}

func buildPRPlan(in Input) protocol.Plan {
	intent := normalizeIntent(in.TestIntent, "smoke")
	return protocol.Plan{Plan: []protocol.PlanStep{
		newStep("step-frontend", "frontend-mcp", fmt.Sprintf("pr.%s.frontend", intent), PriorityNormal, "pr-core", nil, retryFor(PriorityNormal, in.Retry)),
		newStep("step-api", "api-mcp", fmt.Sprintf("pr.%s.api", intent), PriorityNormal, "pr-core", nil, retryFor(PriorityNormal, in.Retry)),
		newStep("step-db", "db-mcp", fmt.Sprintf("pr.%s.db", intent), PriorityNormal, "pr-core", nil, retryFor(PriorityNormal, in.Retry)),
	}}
}

func buildReleasePlan(in Input) protocol.Plan {
	intent := normalizeIntent(in.TestIntent, "full")
	e2eSuite := fmt.Sprintf("release.%s.e2e", intent)
	if intent == "full" {
		e2eSuite = "release.full.e2e"
	}
	return protocol.Plan{Plan: []protocol.PlanStep{
		newStep("step-e2e", "e2e-mcp", e2eSuite, PriorityCritical, "release-critical", nil, retryFor(PriorityCritical, in.Retry)),
		newStep("step-load", "load-mcp", "release.load.baseline", PriorityNormal, "release-load", []string{"step-e2e"}, retryFor(PriorityNormal, in.Retry)),
	}}
}

func buildHotfixPlan(in Input) protocol.Plan {
	areas := make(map[string]struct{}, len(in.ChangedAreas))
	for _, area := range in.ChangedAreas {
		areas[strings.ToLower(area)] = struct{}{}
	}
	steps := []protocol.PlanStep{
		newStep("step-hotfix-api", "api-mcp", "hotfix.critical.api", PriorityCritical, "hotfix-critical", nil, retryFor(PriorityCritical, in.Retry)),
	}
	if _, ok := areas["frontend"]; ok {
		steps = append(steps, newStep("step-hotfix-frontend", "frontend-mcp", "hotfix.critical.frontend", PriorityCritical, "hotfix-critical", nil, retryFor(PriorityCritical, in.Retry)))
	}
	if _, ok := areas["db"]; ok {
		steps = append(steps, newStep("step-hotfix-db", "db-mcp", "hotfix.critical.db", PriorityCritical, "hotfix-critical", nil, retryFor(PriorityCritical, in.Retry)))
	}
	return protocol.Plan{Plan: steps}
}

func newStep(id, mcp, suite, priority, group string, dependsOn []string, retry protocol.Retry) protocol.PlanStep {
	return protocol.PlanStep{
		ID:            id,
		MCP:           mcp,
		Suite:         suite,
		Priority:      priority,
		Retry:         retry,
		ParallelGroup: group,
		DependsOn:     dependsOn,
	}
}

func isReleaseEvent(in Input) bool {
	return strings.EqualFold(in.GitEvent, "release") || strings.HasPrefix(strings.TrimPrefix(in.GitRef, "refs/heads/"), "release/")
}

func normalizeIntent(intent, fallback string) string {
	intent = strings.TrimSpace(strings.ToLower(intent))
	switch intent {
	case "", "smoke":
		return fallback
	case "regression", "full", "critical-path":
		return intent
	default:
		return intent
	}
}

func defaultSuiteForMCP(mcp string, in Input) string {
	if strings.TrimSpace(in.Suite) != "" {
		return in.Suite
	}
	intent := normalizeIntent(in.TestIntent, "smoke")
	switch mcp {
	case "frontend-mcp":
		return fmt.Sprintf("manual.%s.frontend", intent)
	case "api-mcp":
		return fmt.Sprintf("manual.%s.api", intent)
	case "db-mcp":
		return fmt.Sprintf("manual.%s.db", intent)
	case "e2e-mcp":
		return fmt.Sprintf("manual.%s.e2e", intent)
	case "load-mcp":
		return "manual.load.baseline"
	default:
		return fmt.Sprintf("manual.%s.%s", intent, strings.TrimSuffix(mcp, "-mcp"))
	}
}

func retryFor(priority string, override *protocol.Retry) protocol.Retry {
	if override != nil && override.MaxAttempts > 0 {
		return *override
	}
	if priority == PriorityCritical {
		return protocol.Retry{MaxAttempts: 3, BackoffMS: 2000}
	}
	return protocol.Retry{MaxAttempts: 2, BackoffMS: 1000}
}
