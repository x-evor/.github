package evolution

import (
	"testing"

	"xcloudflow/internal/protocol"
)

func TestRecommendationsForFailure(t *testing.T) {
	recommendations := RecommendationsForFailure([]protocol.TaskSummary{
		{MCP: "api-contract-mcp", Status: "failed"},
		{MCP: "desktop-e2e-mcp", Status: "failed"},
	})
	if len(recommendations) != 2 {
		t.Fatalf("expected 2 recommendations, got %d", len(recommendations))
	}
	if recommendations[0].SuspectedLayer == "" || recommendations[0].RecommendedTestFirst == "" {
		t.Fatalf("expected structured recommendation fields, got %#v", recommendations[0])
	}
}

func TestGeneratedTestsIncludesFlutterAndGoLayers(t *testing.T) {
	generated := GeneratedTests("desktop-login", "cover login + settings flow")
	if generated == nil {
		t.Fatal("expected generated tests")
	}
	if len(generated.UnitTests) < 2 {
		t.Fatalf("expected both Go and Flutter unit drafts, got %d", len(generated.UnitTests))
	}
	if len(generated.GoldenTests) == 0 || len(generated.PatrolTests) == 0 {
		t.Fatalf("expected golden and patrol drafts, got %#v", generated)
	}
}
