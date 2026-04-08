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
	EventSource  string
	TestIntent   string
	ChangedAreas []string
	RepoScope    []string
	FeatureName  string
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
	"flutter-widget-mcp",
	"flutter-golden-mcp",
	"flutter-integration-mcp",
	"flutter-patrol-mcp",
	"go-unit-mcp",
	"api-contract-mcp",
	"desktop-e2e-mcp",
	"test-gen-mcp",
	"fix-suggest-mcp",
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
	steps := []protocol.PlanStep{
		newStep("step-change-analysis", "frontend-mcp", fmt.Sprintf("pr.%s.change-analysis", intent), PriorityNormal, "pr-analysis", nil, retryFor(PriorityNormal, in.Retry)),
	}
	if strings.TrimSpace(in.FeatureName) != "" {
		steps = append(steps,
			newStep("step-test-gen", "test-gen-mcp", fmt.Sprintf("pr.%s.test-generation", intent), PriorityNormal, "pr-analysis", []string{"step-change-analysis"}, retryFor(PriorityNormal, in.Retry)),
		)
	}
	steps = append(steps,
		newStep("step-flutter-widget", "flutter-widget-mcp", fmt.Sprintf("pr.%s.flutter-widget", intent), PriorityNormal, "quick-stack", dependsOnForGeneration(in.FeatureName), retryFor(PriorityNormal, in.Retry)),
		newStep("step-flutter-golden", "flutter-golden-mcp", fmt.Sprintf("pr.%s.flutter-golden", intent), PriorityNormal, "quick-stack", dependsOnForGeneration(in.FeatureName), retryFor(PriorityNormal, in.Retry)),
		newStep("step-go-unit", "go-unit-mcp", fmt.Sprintf("pr.%s.go-unit", intent), PriorityCritical, "quick-stack", dependsOnForGeneration(in.FeatureName), retryFor(PriorityCritical, in.Retry)),
		newStep("step-api-contract", "api-contract-mcp", fmt.Sprintf("pr.%s.api-contract", intent), PriorityCritical, "quick-stack", dependsOnForGeneration(in.FeatureName), retryFor(PriorityCritical, in.Retry)),
		newStep("step-flutter-integration", "flutter-integration-mcp", fmt.Sprintf("pr.%s.flutter-integration", intent), PriorityCritical, "critical-path", []string{"step-go-unit", "step-api-contract"}, retryFor(PriorityCritical, in.Retry)),
		newStep("step-desktop-e2e", "desktop-e2e-mcp", fmt.Sprintf("pr.%s.desktop-e2e", intent), PriorityCritical, "desktop-e2e", []string{"step-flutter-integration"}, retryFor(PriorityCritical, in.Retry)),
		newStep("step-flutter-patrol", "flutter-patrol-mcp", fmt.Sprintf("pr.%s.flutter-patrol", intent), PriorityNormal, "desktop-e2e", []string{"step-desktop-e2e"}, retryFor(PriorityNormal, in.Retry)),
		newStep("step-fix-suggest", "fix-suggest-mcp", fmt.Sprintf("pr.%s.fix-suggest", intent), PriorityNormal, "pr-summary", []string{"step-desktop-e2e"}, retryFor(PriorityNormal, in.Retry)),
	)
	return protocol.Plan{Plan: steps}
}

func buildReleasePlan(in Input) protocol.Plan {
	intent := normalizeIntent(in.TestIntent, "full")
	return protocol.Plan{Plan: []protocol.PlanStep{
		newStep("step-release-go-unit", "go-unit-mcp", fmt.Sprintf("release.%s.go-unit", intent), PriorityCritical, "release-quick", nil, retryFor(PriorityCritical, in.Retry)),
		newStep("step-release-api-contract", "api-contract-mcp", fmt.Sprintf("release.%s.api-contract", intent), PriorityCritical, "release-quick", nil, retryFor(PriorityCritical, in.Retry)),
		newStep("step-release-integration", "flutter-integration-mcp", fmt.Sprintf("release.%s.integration", intent), PriorityCritical, "release-critical", []string{"step-release-go-unit", "step-release-api-contract"}, retryFor(PriorityCritical, in.Retry)),
		newStep("step-release-desktop-e2e", "desktop-e2e-mcp", fmt.Sprintf("release.%s.desktop-e2e", intent), PriorityCritical, "release-critical", []string{"step-release-integration"}, retryFor(PriorityCritical, in.Retry)),
		newStep("step-release-patrol", "flutter-patrol-mcp", fmt.Sprintf("release.%s.patrol", intent), PriorityNormal, "release-critical", []string{"step-release-desktop-e2e"}, retryFor(PriorityNormal, in.Retry)),
		newStep("step-load", "load-mcp", "release.load.baseline", PriorityNormal, "release-load", []string{"step-release-desktop-e2e"}, retryFor(PriorityNormal, in.Retry)),
		newStep("step-release-fix-suggest", "fix-suggest-mcp", fmt.Sprintf("release.%s.fix-suggest", intent), PriorityNormal, "release-summary", []string{"step-load"}, retryFor(PriorityNormal, in.Retry)),
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
	case "flutter-widget-mcp":
		return fmt.Sprintf("manual.%s.flutter-widget", intent)
	case "flutter-golden-mcp":
		return fmt.Sprintf("manual.%s.flutter-golden", intent)
	case "flutter-integration-mcp":
		return fmt.Sprintf("manual.%s.flutter-integration", intent)
	case "flutter-patrol-mcp":
		return fmt.Sprintf("manual.%s.flutter-patrol", intent)
	case "go-unit-mcp":
		return fmt.Sprintf("manual.%s.go-unit", intent)
	case "api-contract-mcp":
		return fmt.Sprintf("manual.%s.api-contract", intent)
	case "desktop-e2e-mcp":
		return fmt.Sprintf("manual.%s.desktop-e2e", intent)
	case "test-gen-mcp":
		return fmt.Sprintf("manual.%s.test-generation", intent)
	case "fix-suggest-mcp":
		return fmt.Sprintf("manual.%s.fix-suggest", intent)
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

func dependsOnForGeneration(featureName string) []string {
	if strings.TrimSpace(featureName) == "" {
		return []string{"step-change-analysis"}
	}
	return []string{"step-test-gen"}
}
