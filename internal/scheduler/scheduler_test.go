package scheduler

import "testing"

func TestBuildPlanPR(t *testing.T) {
	plan := BuildPlan(Input{GitEvent: "pr", TestIntent: "smoke"})
	if len(plan.Plan) != 3 {
		t.Fatalf("expected 3 steps, got %d", len(plan.Plan))
	}
	if plan.Plan[0].MCP != "frontend-mcp" || plan.Plan[1].MCP != "api-mcp" || plan.Plan[2].MCP != "db-mcp" {
		t.Fatalf("unexpected plan order: %#v", plan.Plan)
	}
}

func TestBuildPlanRelease(t *testing.T) {
	plan := BuildPlan(Input{GitRef: "release/v1.2.3"})
	if len(plan.Plan) != 2 {
		t.Fatalf("expected 2 steps, got %d", len(plan.Plan))
	}
	if plan.Plan[0].MCP != "e2e-mcp" || plan.Plan[1].DependsOn[0] != "step-e2e" {
		t.Fatalf("unexpected release plan: %#v", plan.Plan)
	}
}

func TestBuildPlanHotfix(t *testing.T) {
	plan := BuildPlan(Input{GitEvent: "hotfix", ChangedAreas: []string{"frontend", "db"}})
	if len(plan.Plan) != 3 {
		t.Fatalf("expected 3 steps, got %d", len(plan.Plan))
	}
	for _, step := range plan.Plan {
		if step.Priority != PriorityCritical {
			t.Fatalf("expected critical priority, got %s", step.Priority)
		}
	}
}
