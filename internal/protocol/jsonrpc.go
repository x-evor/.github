package protocol

import "time"

const JSONRPCVersion = "2.0"

type Request struct {
	JSONRPC string         `json:"jsonrpc"`
	ID      any            `json:"id,omitempty"`
	Method  string         `json:"method"`
	Params  map[string]any `json:"params,omitempty"`
}

type Response struct {
	JSONRPC string    `json:"jsonrpc"`
	ID      any       `json:"id,omitempty"`
	Result  any       `json:"result,omitempty"`
	Error   *RPCError `json:"error,omitempty"`
}

type Notification struct {
	JSONRPC string `json:"jsonrpc"`
	Method  string `json:"method"`
	Params  any    `json:"params,omitempty"`
}

type RPCError struct {
	Code    int            `json:"code"`
	Message string         `json:"message"`
	Data    map[string]any `json:"data,omitempty"`
}

func NewError(code int, message string, data map[string]any) *RPCError {
	return &RPCError{Code: code, Message: message, Data: data}
}

const (
	ErrParse          = -32700
	ErrInvalidRequest = -32600
	ErrMethodNotFound = -32601
	ErrInvalidParams  = -32602
	ErrInternal       = -32603
	ErrConflict       = -32009
	ErrNotFound       = -32004
)

type RunParams struct {
	Suite        string   `json:"suite"`
	Env          string   `json:"env"`
	Tags         []string `json:"tags,omitempty"`
	MCP          string   `json:"mcp,omitempty"`
	MCPs         []string `json:"mcps,omitempty"`
	RunAll       bool     `json:"run_all,omitempty"`
	GitEvent     string   `json:"git_event,omitempty"`
	GitRef       string   `json:"git_ref,omitempty"`
	TestIntent   string   `json:"test_intent,omitempty"`
	ChangedAreas []string `json:"changed_areas,omitempty"`
	Async        bool     `json:"async,omitempty"`
	Stream       bool     `json:"stream,omitempty"`
	TimeoutMS    int      `json:"timeout_ms,omitempty"`
	Parallelism  int      `json:"parallelism,omitempty"`
	Retry        *Retry   `json:"retry,omitempty"`
	FeatureName  string   `json:"feature_name,omitempty"`
	FeatureID    string   `json:"feature_id,omitempty"`
	FeatureNotes string   `json:"feature_notes,omitempty"`
	RepoScope    []string `json:"repo_scope,omitempty"`
	PRNumber     string   `json:"pr_number,omitempty"`
	EventSource  string   `json:"event_source,omitempty"`
	AgentLoop    bool     `json:"agent_loop,omitempty"`
}

type Retry struct {
	MaxAttempts int `json:"max_attempts"`
	BackoffMS   int `json:"backoff_ms"`
}

type StatusParams struct {
	JobID string `json:"job_id"`
}

type CancelParams struct {
	JobID string `json:"job_id"`
}

type Plan struct {
	Plan []PlanStep `json:"plan"`
}

type PlanStep struct {
	ID            string   `json:"id"`
	MCP           string   `json:"mcp"`
	Suite         string   `json:"suite"`
	Priority      string   `json:"priority,omitempty"`
	Retry         Retry    `json:"retry,omitempty"`
	ParallelGroup string   `json:"parallel_group,omitempty"`
	DependsOn     []string `json:"depends_on,omitempty"`
}

type RunResult struct {
	Status             string           `json:"status"`
	Duration           int64            `json:"duration"`
	Logs               []string         `json:"logs"`
	Errors             []string         `json:"errors"`
	JobID              string           `json:"job_id,omitempty"`
	Plan               []PlanStep       `json:"plan,omitempty"`
	StartedAt          time.Time        `json:"started_at,omitempty"`
	FinishedAt         time.Time        `json:"finished_at,omitempty"`
	StreamURL          string           `json:"stream_url,omitempty"`
	StatusURL          string           `json:"status_url,omitempty"`
	Tasks              []TaskSummary    `json:"tasks,omitempty"`
	Suggestions        []string         `json:"suggestions,omitempty"`
	Artifacts          []Artifact       `json:"artifacts,omitempty"`
	Recommendations    []Recommendation `json:"recommendations,omitempty"`
	MergeBlockedReason string           `json:"merge_blocked_reason,omitempty"`
	Generated          *GeneratedSet    `json:"generated,omitempty"`
}

type TaskSummary struct {
	ID       string   `json:"id"`
	MCP      string   `json:"mcp"`
	Suite    string   `json:"suite"`
	Status   string   `json:"status"`
	Attempts int      `json:"attempts"`
	Logs     []string `json:"logs,omitempty"`
	Errors   []string `json:"errors,omitempty"`
}

type StreamEvent struct {
	JobID      string    `json:"job_id"`
	Type       string    `json:"type"`
	Message    string    `json:"message,omitempty"`
	TaskID     string    `json:"task_id,omitempty"`
	TaskStatus string    `json:"task_status,omitempty"`
	At         time.Time `json:"at"`
}

type GeneratedSet struct {
	UnitTests        []GeneratedTest `json:"unit_tests,omitempty"`
	IntegrationTests []GeneratedTest `json:"integration_tests,omitempty"`
	E2ETests         []GeneratedTest `json:"e2e_tests,omitempty"`
	GoldenTests      []GeneratedTest `json:"golden_tests,omitempty"`
	PatrolTests      []GeneratedTest `json:"patrol_tests,omitempty"`
}

type GeneratedTest struct {
	Repo        string   `json:"repo,omitempty"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Layer       string   `json:"layer,omitempty"`
	TargetPaths []string `json:"target_paths,omitempty"`
	Inputs      []string `json:"inputs,omitempty"`
	Assertions  []string `json:"assertions,omitempty"`
	Environment []string `json:"environment,omitempty"`
}

type Recommendation struct {
	Title                string   `json:"title"`
	SuspectedLayer       string   `json:"suspected_layer,omitempty"`
	FailingContract      string   `json:"failing_contract,omitempty"`
	LikelyFiles          []string `json:"likely_files,omitempty"`
	RecommendedTestFirst string   `json:"recommended_test_first,omitempty"`
	SafeFixOrder         []string `json:"safe_fix_order,omitempty"`
	Summary              string   `json:"summary,omitempty"`
}

type Artifact struct {
	Name string `json:"name"`
	Path string `json:"path,omitempty"`
	Kind string `json:"kind,omitempty"`
}
