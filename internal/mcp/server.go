package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"path"
	"sort"
	"strings"
	"sync"
	"time"

	"xcloudflow/internal/evolution"
	"xcloudflow/internal/protocol"
	"xcloudflow/internal/scheduler"
	"xcloudflow/internal/store"
)

type ServerOptions struct {
	Store *store.Store
}

type Server struct {
	store *store.Store

	mu   sync.RWMutex
	jobs map[string]*job
}

type job struct {
	id         string
	cancel     context.CancelFunc
	done       chan struct{}
	runResult  protocol.RunResult
	subs       map[chan protocol.Notification]struct{}
	subsMu     sync.Mutex
	cancelled  bool
	cancelLock sync.Mutex
}

func NewServer(opts ServerOptions) *Server {
	return &Server{
		store: opts.Store,
		jobs:  map[string]*job{},
	}
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req protocol.Request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeResponse(w, protocol.Response{JSONRPC: protocol.JSONRPCVersion, Error: protocol.NewError(protocol.ErrParse, "invalid json", nil)})
		return
	}
	if req.JSONRPC == "" {
		req.JSONRPC = protocol.JSONRPCVersion
	}
	resp := s.handleRequest(r.Context(), req)
	s.writeResponse(w, resp)
}

func (s *Server) StreamHTTP(w http.ResponseWriter, r *http.Request) {
	jobID := path.Base(r.URL.Path)
	j, ok := s.getJob(jobID)
	if !ok {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "application/x-ndjson")
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}

	ch := make(chan protocol.Notification, 32)
	j.addSubscriber(ch)
	defer j.removeSubscriber(ch)

	enc := json.NewEncoder(w)
	for {
		select {
		case <-r.Context().Done():
			return
		case <-j.done:
			_ = enc.Encode(protocol.Notification{
				JSONRPC: protocol.JSONRPCVersion,
				Method:  "test.event",
				Params: protocol.StreamEvent{
					JobID:   jobID,
					Type:    "job.completed",
					Message: "job completed",
					At:      time.Now().UTC(),
				},
			})
			flusher.Flush()
			return
		case notif := <-ch:
			_ = enc.Encode(notif)
			flusher.Flush()
		}
	}
}

func (s *Server) handleRequest(ctx context.Context, req protocol.Request) protocol.Response {
	switch req.Method {
	case "test.run":
		return s.handleRun(ctx, req)
	case "test.status":
		return s.handleStatus(req)
	case "test.cancel":
		return s.handleCancel(req)
	default:
		return protocol.Response{
			JSONRPC: protocol.JSONRPCVersion,
			ID:      req.ID,
			Error:   protocol.NewError(protocol.ErrMethodNotFound, "method not found", map[string]any{"method": req.Method}),
		}
	}
}

func (s *Server) handleRun(ctx context.Context, req protocol.Request) protocol.Response {
	params, err := decodeRunParams(req.Params)
	if err != nil {
		return protocol.Response{JSONRPC: protocol.JSONRPCVersion, ID: req.ID, Error: protocol.NewError(protocol.ErrInvalidParams, err.Error(), nil)}
	}

	execCtx := ctx
	timeout := time.Duration(params.TimeoutMS) * time.Millisecond
	if timeout > 0 {
		var cancel context.CancelFunc
		execCtx, cancel = context.WithTimeout(ctx, timeout)
		defer cancel()
	}

	if params.Async || params.Stream {
		j := s.newJob()
		jobCtx, cancel := context.WithCancel(context.Background())
		j.cancel = cancel
		go s.execute(jobCtx, j, params)
		result := protocol.RunResult{
			Status:    "accepted",
			Duration:  0,
			Logs:      []string{"job accepted"},
			Errors:    nil,
			JobID:     j.id,
			StartedAt: time.Now().UTC(),
			StreamURL: "/mcp/stream/" + j.id,
			StatusURL: "/mcp/status/" + j.id,
			Artifacts: defaultArtifacts(""),
		}
		if params.FeatureName != "" || params.FeatureNotes != "" {
			result.Generated = evolution.GeneratedTests(params.FeatureName, params.FeatureNotes)
		}
		return protocol.Response{JSONRPC: protocol.JSONRPCVersion, ID: req.ID, Result: result}
	}

	j := s.newJob()
	j.cancel = func() {}
	s.execute(execCtx, j, params)
	<-j.done
	return protocol.Response{JSONRPC: protocol.JSONRPCVersion, ID: req.ID, Result: j.runResult}
}

func (s *Server) handleStatus(req protocol.Request) protocol.Response {
	var params protocol.StatusParams
	if err := decodeInto(req.Params, &params); err != nil || params.JobID == "" {
		return protocol.Response{JSONRPC: protocol.JSONRPCVersion, ID: req.ID, Error: protocol.NewError(protocol.ErrInvalidParams, "job_id is required", nil)}
	}
	j, ok := s.getJob(params.JobID)
	if !ok {
		return protocol.Response{JSONRPC: protocol.JSONRPCVersion, ID: req.ID, Error: protocol.NewError(protocol.ErrNotFound, "job not found", nil)}
	}
	return protocol.Response{JSONRPC: protocol.JSONRPCVersion, ID: req.ID, Result: j.runResult}
}

func (s *Server) handleCancel(req protocol.Request) protocol.Response {
	var params protocol.CancelParams
	if err := decodeInto(req.Params, &params); err != nil || params.JobID == "" {
		return protocol.Response{JSONRPC: protocol.JSONRPCVersion, ID: req.ID, Error: protocol.NewError(protocol.ErrInvalidParams, "job_id is required", nil)}
	}
	j, ok := s.getJob(params.JobID)
	if !ok {
		return protocol.Response{JSONRPC: protocol.JSONRPCVersion, ID: req.ID, Error: protocol.NewError(protocol.ErrNotFound, "job not found", nil)}
	}
	j.markCancelled()
	j.cancel()
	return protocol.Response{
		JSONRPC: protocol.JSONRPCVersion,
		ID:      req.ID,
		Result: protocol.RunResult{
			Status:   "cancelled",
			Duration: j.runResult.Duration,
			Logs:     append(append([]string{}, j.runResult.Logs...), "job cancelled"),
			Errors:   j.runResult.Errors,
			JobID:    j.id,
		},
	}
}

func (s *Server) execute(ctx context.Context, j *job, params protocol.RunParams) {
	started := time.Now().UTC()
	plan := scheduler.BuildPlan(scheduler.Input{
		GitEvent:     params.GitEvent,
		GitRef:       params.GitRef,
		EventSource:  params.EventSource,
		TestIntent:   params.TestIntent,
		ChangedAreas: params.ChangedAreas,
		RepoScope:    params.RepoScope,
		FeatureName:  params.FeatureName,
		Env:          params.Env,
		MCP:          params.MCP,
		MCPs:         params.MCPs,
		RunAll:       params.RunAll,
		Suite:        params.Suite,
		Retry:        params.Retry,
	})
	j.runResult = protocol.RunResult{
		Status:    "running",
		StartedAt: started,
		JobID:     j.id,
		Plan:      plan.Plan,
		Logs:      []string{fmt.Sprintf("started plan with %d step(s)", len(plan.Plan))},
	}
	j.notify("job.started", "job started", "", "running")

	maxParallel := params.Parallelism
	if maxParallel <= 0 {
		maxParallel = 3
	}

	results, finalStatus, logs, errs := executePlan(ctx, j, plan.Plan, maxParallel)
	finished := time.Now().UTC()
	j.runResult = protocol.RunResult{
		Status:          finalStatus,
		Duration:        finished.Sub(started).Milliseconds(),
		Logs:            logs,
		Errors:          errs,
		JobID:           j.id,
		Plan:            plan.Plan,
		StartedAt:       started,
		FinishedAt:      finished,
		Tasks:           results,
		Suggestions:     evolution.SuggestionsForFailure(results),
		Recommendations: evolution.RecommendationsForFailure(results),
		Artifacts:       defaultArtifacts(""),
		Generated:       evolution.GeneratedTests(params.FeatureName, params.FeatureNotes),
	}
	if params.AgentLoop {
		j.runResult.Logs = append(j.runResult.Logs,
			"agent-loop: failure suggestions generated automatically",
			"agent-loop: feature test drafts generated automatically when feature metadata is present",
			"agent-loop: merge should remain blocked until the plan returns success",
		)
		if finalStatus != "success" {
			j.runResult.MergeBlockedReason = "agent-loop gate failed: one or more required critical-path tasks did not succeed"
		}
	}
	j.notify("job.finished", "job finished", "", finalStatus)
	close(j.done)
}

func executePlan(ctx context.Context, j *job, steps []protocol.PlanStep, maxParallel int) ([]protocol.TaskSummary, string, []string, []string) {
	stepByID := make(map[string]protocol.PlanStep, len(steps))
	statusByID := make(map[string]string, len(steps))
	resultByID := make(map[string]protocol.TaskSummary, len(steps))
	for _, step := range steps {
		stepByID[step.ID] = step
		statusByID[step.ID] = "pending"
	}

	overallLogs := []string{}
	overallErrs := []string{}

	for {
		select {
		case <-ctx.Done():
			overallErrs = append(overallErrs, "execution cancelled or timed out")
			return summariesInPlanOrder(steps, resultByID, statusByID), "cancelled", append(overallLogs, "execution stopped"), overallErrs
		default:
		}

		ready := collectReady(steps, statusByID)
		if len(ready) == 0 {
			break
		}
		sort.SliceStable(ready, func(i, k int) bool {
			if ready[i].Priority == ready[k].Priority {
				return ready[i].ID < ready[k].ID
			}
			return ready[i].Priority == scheduler.PriorityCritical
		})

		sem := make(chan struct{}, maxParallel)
		var wg sync.WaitGroup
		var mu sync.Mutex
		for _, step := range ready {
			statusByID[step.ID] = "running"
			wg.Add(1)
			go func(step protocol.PlanStep) {
				defer wg.Done()
				sem <- struct{}{}
				defer func() { <-sem }()
				summary := runStep(ctx, j, step)
				mu.Lock()
				resultByID[step.ID] = summary
				statusByID[step.ID] = summary.Status
				overallLogs = append(overallLogs, summary.Logs...)
				overallErrs = append(overallErrs, summary.Errors...)
				mu.Unlock()
			}(step)
		}
		wg.Wait()

		for _, step := range ready {
			if resultByID[step.ID].Status == "failed" && step.Priority == scheduler.PriorityCritical {
				return summariesInPlanOrder(steps, resultByID, statusByID), "failed", overallLogs, overallErrs
			}
		}
	}

	final := "success"
	for _, summary := range resultByID {
		if summary.Status == "failed" {
			final = "failed"
			break
		}
	}
	return summariesInPlanOrder(steps, resultByID, statusByID), final, overallLogs, overallErrs
}

func collectReady(steps []protocol.PlanStep, statusByID map[string]string) []protocol.PlanStep {
	var ready []protocol.PlanStep
	for _, step := range steps {
		if statusByID[step.ID] != "pending" {
			continue
		}
		blocked := false
		for _, dep := range step.DependsOn {
			switch statusByID[dep] {
			case "success":
			case "failed", "cancelled":
				blocked = true
				statusByID[step.ID] = "skipped"
			default:
				blocked = true
			}
			if blocked {
				break
			}
		}
		if !blocked {
			ready = append(ready, step)
		}
	}
	return ready
}

func runStep(ctx context.Context, j *job, step protocol.PlanStep) protocol.TaskSummary {
	j.notify("task.started", fmt.Sprintf("%s started", step.ID), step.ID, "running")
	summary := protocol.TaskSummary{
		ID:     step.ID,
		MCP:    step.MCP,
		Suite:  step.Suite,
		Status: "failed",
	}
	for attempt := 1; attempt <= step.Retry.MaxAttempts; attempt++ {
		select {
		case <-ctx.Done():
			summary.Status = "cancelled"
			summary.Errors = append(summary.Errors, "context cancelled")
			return summary
		default:
		}

		summary.Attempts = attempt
		summary.Logs = append(summary.Logs, fmt.Sprintf("%s attempt %d", step.ID, attempt))
		time.Sleep(25 * time.Millisecond)

		if shouldSucceed(step, attempt) {
			summary.Status = "success"
			summary.Logs = append(summary.Logs, fmt.Sprintf("%s passed", step.ID))
			j.notify("task.finished", fmt.Sprintf("%s passed", step.ID), step.ID, "success")
			return summary
		}

		summary.Errors = append(summary.Errors, fmt.Sprintf("%s failed attempt %d", step.ID, attempt))
		if attempt < step.Retry.MaxAttempts {
			time.Sleep(time.Duration(step.Retry.BackoffMS) * time.Millisecond)
		}
	}
	j.notify("task.finished", fmt.Sprintf("%s failed", step.ID), step.ID, "failed")
	return summary
}

func shouldSucceed(step protocol.PlanStep, attempt int) bool {
	if strings.Contains(step.Suite, "fail") {
		return false
	}
	if strings.Contains(step.Suite, "flaky") {
		return attempt > 1
	}
	return true
}

func summariesInPlanOrder(steps []protocol.PlanStep, resultByID map[string]protocol.TaskSummary, statusByID map[string]string) []protocol.TaskSummary {
	out := make([]protocol.TaskSummary, 0, len(steps))
	for _, step := range steps {
		if summary, ok := resultByID[step.ID]; ok {
			out = append(out, summary)
			continue
		}
		out = append(out, protocol.TaskSummary{
			ID:     step.ID,
			MCP:    step.MCP,
			Suite:  step.Suite,
			Status: statusByID[step.ID],
		})
	}
	return out
}

func decodeRunParams(params map[string]any) (protocol.RunParams, error) {
	var out protocol.RunParams
	if err := decodeInto(params, &out); err != nil {
		return out, err
	}
	if strings.TrimSpace(out.Env) == "" {
		out.Env = "dev"
	}
	if strings.TrimSpace(out.Suite) == "" && out.GitEvent == "" && out.MCP == "" && len(out.MCPs) == 0 && !out.RunAll {
		return out, fmt.Errorf("suite, event, mcp, mcps, or run_all is required")
	}
	return out, nil
}

func decodeInto(params map[string]any, out any) error {
	raw, err := json.Marshal(params)
	if err != nil {
		return err
	}
	return json.Unmarshal(raw, out)
}

func (s *Server) writeResponse(w http.ResponseWriter, resp protocol.Response) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func (s *Server) newJob() *job {
	j := &job{
		id:   fmt.Sprintf("job-%d", time.Now().UnixNano()),
		done: make(chan struct{}),
		subs: map[chan protocol.Notification]struct{}{},
	}
	s.mu.Lock()
	s.jobs[j.id] = j
	s.mu.Unlock()
	return j
}

func (s *Server) getJob(id string) (*job, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	j, ok := s.jobs[id]
	return j, ok
}

func (j *job) notify(eventType, message, taskID, taskStatus string) {
	notif := protocol.Notification{
		JSONRPC: protocol.JSONRPCVersion,
		Method:  "test.event",
		Params: protocol.StreamEvent{
			JobID:      j.id,
			Type:       eventType,
			Message:    message,
			TaskID:     taskID,
			TaskStatus: taskStatus,
			At:         time.Now().UTC(),
		},
	}
	j.subsMu.Lock()
	defer j.subsMu.Unlock()
	for ch := range j.subs {
		select {
		case ch <- notif:
		default:
		}
	}
}

func (j *job) addSubscriber(ch chan protocol.Notification) {
	j.subsMu.Lock()
	defer j.subsMu.Unlock()
	j.subs[ch] = struct{}{}
}

func (j *job) removeSubscriber(ch chan protocol.Notification) {
	j.subsMu.Lock()
	defer j.subsMu.Unlock()
	delete(j.subs, ch)
	close(ch)
}

func (j *job) markCancelled() {
	j.cancelLock.Lock()
	defer j.cancelLock.Unlock()
	j.cancelled = true
}

func defaultArtifacts(baseDir string) []protocol.Artifact {
	names := []struct {
		name string
		kind string
	}{
		{name: "run-result.json", kind: "run-result"},
		{name: "generated-tests.json", kind: "generated-tests"},
		{name: "fix-suggestions.json", kind: "fix-suggestions"},
		{name: "task-timeline.json", kind: "task-timeline"},
	}
	out := make([]protocol.Artifact, 0, len(names))
	for _, item := range names {
		artifact := protocol.Artifact{Name: item.name, Kind: item.kind}
		if baseDir != "" {
			artifact.Path = path.Join(baseDir, item.name)
		}
		out = append(out, artifact)
	}
	return out
}
