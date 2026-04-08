package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"xcloudflow/internal/config"
	"xcloudflow/internal/protocol"
)

func main() {
	if len(os.Args) < 2 || os.Args[1] != "run" {
		usage()
		os.Exit(2)
	}

	fs := flag.NewFlagSet("run", flag.ExitOnError)
	var (
		suite       = fs.String("suite", "", "suite name")
		env         = fs.String("env", "dev", "target environment")
		mcp         = fs.String("mcp", "", "single MCP target")
		mcps        = fs.String("mcps", "", "comma-separated MCP targets")
		runAll      = fs.Bool("all", false, "run all MCPs")
		event       = fs.String("event", "", "git event: pr|release|hotfix")
		gitRef      = fs.String("git-ref", "", "git ref")
		intent      = fs.String("intent", "smoke", "test intent")
		tags        = fs.String("tags", "", "comma-separated tags")
		changed     = fs.String("changed-areas", "", "comma-separated changed areas")
		timeoutMS   = fs.Int("timeout", 30000, "timeout in milliseconds")
		retry       = fs.Int("retry", 0, "override retry max attempts")
		parallelism = fs.Int("parallelism", 3, "max parallel tasks")
		jsonOut     = fs.String("json-out", "", "write JSON report to path")
		gateway     = fs.String("gateway", "", "gateway base URL")
		stream      = fs.Bool("stream", true, "stream job progress")
		featureName = fs.String("feature-name", "", "feature name for generated test drafts")
		featureNote = fs.String("feature-notes", "", "feature notes for generated test drafts")
		agentLoop   = fs.Bool("agent-loop", true, "enable agent loop behavior")
	)
	_ = fs.Parse(os.Args[2:])

	cfg, err := config.Load(*env)
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		os.Exit(1)
	}
	baseURL := cfg.Gateway.BaseURL
	if *gateway != "" {
		baseURL = *gateway
	}

	runParams := protocol.RunParams{
		Suite:        *suite,
		Env:          *env,
		Tags:         splitCSV(*tags),
		MCP:          *mcp,
		MCPs:         splitCSV(*mcps),
		RunAll:       *runAll,
		GitEvent:     *event,
		GitRef:       *gitRef,
		TestIntent:   *intent,
		ChangedAreas: splitCSV(*changed),
		Async:        *stream,
		Stream:       *stream,
		TimeoutMS:    *timeoutMS,
		Parallelism:  *parallelism,
		FeatureName:  *featureName,
		FeatureNotes: *featureNote,
		AgentLoop:    *agentLoop,
	}
	if *retry > 0 {
		runParams.Retry = &protocol.Retry{MaxAttempts: *retry, BackoffMS: 1000}
	}

	result, err := run(baseURL, runParams, *stream)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	printConsoleReport(result)
	if *jsonOut != "" {
		if err := writeJSON(*jsonOut, result); err != nil {
			fmt.Fprintln(os.Stderr, "write report:", err)
			os.Exit(1)
		}
	}
	if result.Status != "success" {
		os.Exit(1)
	}
}

func run(baseURL string, params protocol.RunParams, stream bool) (protocol.RunResult, error) {
	reqBody := protocol.Request{
		JSONRPC: protocol.JSONRPCVersion,
		ID:      "run-1",
		Method:  "test.run",
		Params:  mustMap(params),
	}
	resp, err := rpc(baseURL+"/mcp", reqBody)
	if err != nil {
		return protocol.RunResult{}, err
	}
	if resp.Error != nil {
		return protocol.RunResult{}, fmt.Errorf("%s", resp.Error.Message)
	}
	result := decodeResult(resp.Result)
	if !stream || result.JobID == "" {
		return result, nil
	}
	if err := streamJob(baseURL+result.StreamURL, os.Stdout); err != nil {
		return protocol.RunResult{}, err
	}
	for {
		statusResp, err := rpc(baseURL+"/mcp", protocol.Request{
			JSONRPC: protocol.JSONRPCVersion,
			ID:      "status-1",
			Method:  "test.status",
			Params:  mustMap(protocol.StatusParams{JobID: result.JobID}),
		})
		if err != nil {
			return protocol.RunResult{}, err
		}
		if statusResp.Error != nil {
			return protocol.RunResult{}, fmt.Errorf("%s", statusResp.Error.Message)
		}
		latest := decodeResult(statusResp.Result)
		if latest.Status != "running" && latest.Status != "accepted" {
			return latest, nil
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func rpc(url string, req protocol.Request) (protocol.Response, error) {
	body, _ := json.Marshal(req)
	httpResp, err := http.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		return protocol.Response{}, err
	}
	defer httpResp.Body.Close()
	var resp protocol.Response
	if err := json.NewDecoder(httpResp.Body).Decode(&resp); err != nil {
		return protocol.Response{}, err
	}
	return resp, nil
}

func streamJob(url string, out io.Writer) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := scanner.Bytes()
		var notif protocol.Notification
		if err := json.Unmarshal(line, &notif); err != nil {
			continue
		}
		raw, _ := json.Marshal(notif.Params)
		fmt.Fprintf(out, "stream %s %s\n", notif.Method, string(raw))
	}
	return scanner.Err()
}

func printConsoleReport(result protocol.RunResult) {
	fmt.Printf("status: %s\n", result.Status)
	fmt.Printf("duration_ms: %d\n", result.Duration)
	for _, log := range result.Logs {
		fmt.Printf("log: %s\n", log)
	}
	for _, err := range result.Errors {
		fmt.Printf("error: %s\n", err)
	}
	for _, task := range result.Tasks {
		fmt.Printf("task: %s %s %s attempts=%d\n", task.ID, task.MCP, task.Status, task.Attempts)
	}
	for _, suggestion := range result.Suggestions {
		fmt.Printf("suggestion: %s\n", suggestion)
	}
	if result.Generated != nil {
		for _, generated := range result.Generated.UnitTests {
			fmt.Printf("generated-unit: %s %s\n", generated.Name, generated.Description)
		}
		for _, generated := range result.Generated.IntegrationTests {
			fmt.Printf("generated-integration: %s %s\n", generated.Name, generated.Description)
		}
		for _, generated := range result.Generated.E2ETests {
			fmt.Printf("generated-e2e: %s %s\n", generated.Name, generated.Description)
		}
	}
}

func writeJSON(path string, result protocol.RunResult) error {
	raw, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, raw, 0o644)
}

func splitCSV(input string) []string {
	if strings.TrimSpace(input) == "" {
		return nil
	}
	parts := strings.Split(input, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}

func mustMap(v any) map[string]any {
	raw, _ := json.Marshal(v)
	out := map[string]any{}
	_ = json.Unmarshal(raw, &out)
	return out
}

func decodeResult(in any) protocol.RunResult {
	raw, _ := json.Marshal(in)
	var out protocol.RunResult
	_ = json.Unmarshal(raw, &out)
	return out
}

func usage() {
	fmt.Println("Usage: full-stack-test run --suite=e2e --env=pre [--mcp=api-mcp|--mcps=a,b|--all]")
}
