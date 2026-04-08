package mcp

import (
	"context"
	"encoding/json"
	"testing"

	"xcloudflow/internal/protocol"
)

func TestHandleRunSync(t *testing.T) {
	srv := NewServer(ServerOptions{})
	resp := srv.handleRequest(context.Background(), protocol.Request{
		JSONRPC: protocol.JSONRPCVersion,
		ID:      "1",
		Method:  "test.run",
		Params: map[string]any{
			"git_event": "pr",
			"env":       "dev",
			"suite":     "smoke",
		},
	})
	if resp.Error != nil {
		t.Fatalf("unexpected error: %+v", resp.Error)
	}
	result := decodeResponseResult(resp.Result)
	if result.Status != "success" {
		t.Fatalf("expected success, got %s", result.Status)
	}
	if len(result.Plan) < 8 {
		t.Fatalf("expected expanded PR plan, got %d", len(result.Plan))
	}
}

func TestHandleRunAsyncAndStatus(t *testing.T) {
	srv := NewServer(ServerOptions{})
	resp := srv.handleRequest(context.Background(), protocol.Request{
		JSONRPC: protocol.JSONRPCVersion,
		ID:      "1",
		Method:  "test.run",
		Params: map[string]any{
			"git_event": "release",
			"env":       "pre",
			"async":     true,
			"stream":    true,
			"suite":     "e2e",
		},
	})
	if resp.Error != nil {
		t.Fatalf("unexpected error: %+v", resp.Error)
	}
	runResult := decodeResponseResult(resp.Result)
	if runResult.JobID == "" {
		t.Fatal("expected job id")
	}
	statusResp := srv.handleRequest(context.Background(), protocol.Request{
		JSONRPC: protocol.JSONRPCVersion,
		ID:      "2",
		Method:  "test.status",
		Params: map[string]any{
			"job_id": runResult.JobID,
		},
	})
	if statusResp.Error != nil {
		t.Fatalf("unexpected status error: %+v", statusResp.Error)
	}
}

func decodeResponseResult(in any) protocol.RunResult {
	req := protocol.Response{Result: in}
	raw, _ := jsonMarshal(req.Result)
	var out protocol.RunResult
	_ = jsonUnmarshal(raw, &out)
	return out
}

func jsonMarshal(v any) ([]byte, error)      { return json.Marshal(v) }
func jsonUnmarshal(data []byte, v any) error { return json.Unmarshal(data, v) }
