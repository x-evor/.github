package evolution

import (
	"fmt"
	"strings"

	"xcloudflow/internal/protocol"
)

func RecommendationsForFailure(tasks []protocol.TaskSummary) []protocol.Recommendation {
	var out []protocol.Recommendation
	seen := map[string]struct{}{}
	for _, task := range tasks {
		if task.Status != "failed" {
			continue
		}
		for _, recommendation := range recommendationsForTask(task) {
			key := recommendation.Title + "|" + recommendation.SuspectedLayer + "|" + recommendation.FailingContract
			if _, ok := seen[key]; ok {
				continue
			}
			seen[key] = struct{}{}
			out = append(out, recommendation)
		}
	}
	return out
}

func SuggestionsForFailure(tasks []protocol.TaskSummary) []string {
	recommendations := RecommendationsForFailure(tasks)
	out := make([]string, 0, len(recommendations))
	for _, recommendation := range recommendations {
		summary := recommendation.Title
		if recommendation.Summary != "" {
			summary = recommendation.Summary
		}
		out = append(out, summary)
	}
	return out
}

func GeneratedTests(featureName, notes string) *protocol.GeneratedSet {
	featureName = strings.TrimSpace(featureName)
	notes = strings.TrimSpace(notes)
	if featureName == "" && notes == "" {
		return nil
	}
	label := featureName
	if label == "" {
		label = "unnamed-feature"
	}
	context := "Validate the new feature path end to end."
	if notes != "" {
		context = notes
	}
	return &protocol.GeneratedSet{
		UnitTests: []protocol.GeneratedTest{
			{
				Repo:        "accounts.svc.plus",
				Name:        fmt.Sprintf("%s-go-unit-handler-service", label),
				Description: fmt.Sprintf("Generate Go handler/service/repository unit tests for %s. %s", label, context),
				Layer:       "unit",
				TargetPaths: []string{"internal/handler/*_test.go", "internal/service/*_test.go", "internal/repository/*_test.go"},
				Inputs:      []string{"输入条件", "依赖 fixture", "期望状态码/响应字段"},
				Assertions:  []string{"覆盖核心鉴权/登录分支", "失败路径先补回归测试"},
			},
			{
				Repo:        "xworkmate.svc.plus",
				Name:        fmt.Sprintf("%s-flutter-widget-state", label),
				Description: fmt.Sprintf("Generate Flutter widget tests for %s. %s", label, context),
				Layer:       "unit",
				TargetPaths: []string{"test/widget/**/*_test.dart"},
				Inputs:      []string{"页面名", "关键控件 key", "依赖假数据"},
				Assertions:  []string{"表单状态", "导航状态", "view model/UI state"},
			},
		},
		IntegrationTests: []protocol.GeneratedTest{
			{
				Repo:        "accounts.svc.plus",
				Name:        fmt.Sprintf("%s-accounts-integration-contract", label),
				Description: fmt.Sprintf("Generate Go API integration/contract tests for %s. %s", label, context),
				Layer:       "integration",
				TargetPaths: []string{"test/integration/**/*_test.go"},
				Inputs:      []string{"登录/鉴权", "session/token 校验", "当前用户信息获取"},
				Assertions:  []string{"状态码", "响应字段", "最小闭环"},
			},
			{
				Repo:        "xworkmate.svc.plus",
				Name:        fmt.Sprintf("%s-flutter-integration-flow", label),
				Description: fmt.Sprintf("Generate Flutter integration tests for %s. %s", label, context),
				Layer:       "integration",
				TargetPaths: []string{"integration_test/**/*_test.dart"},
				Inputs:      []string{"启动与 shell 渲染", "登录/会话恢复", "主导航切换", "设置页核心交互"},
				Assertions:  []string{"登录成功", "导航流转", "设置保存", "失败态提示"},
			},
		},
		E2ETests: []protocol.GeneratedTest{
			{
				Repo:        "github-org-cloud-neutral-toolkit",
				Name:        fmt.Sprintf("%s-desktop-e2e-user-journey", label),
				Description: fmt.Sprintf("Generate cross-repo desktop e2e tests for %s. %s", label, context),
				Layer:       "e2e",
				TargetPaths: []string{"templates/testing/xworkmate/desktop-e2e.md", "templates/testing/accounts/api-contract.md"},
				Inputs:      []string{"跨仓登录", "导航", "设置", "会话链路"},
				Assertions:  []string{"主用户旅程通过", "失败链路可定位到首个关键依赖"},
			},
		},
		GoldenTests: []protocol.GeneratedTest{
			{
				Repo:        "xworkmate.svc.plus",
				Name:        fmt.Sprintf("%s-flutter-golden-ui-baseline", label),
				Description: fmt.Sprintf("Generate Flutter golden tests for %s. %s", label, context),
				Layer:       "golden",
				TargetPaths: []string{"test/golden/**/*_test.dart", "test/golden/goldens/*"},
				Inputs:      []string{"页面名", "主题/尺寸", "基线截图名称"},
				Assertions:  []string{"登录页", "主工作区", "设置页核心视觉基线"},
			},
		},
		PatrolTests: []protocol.GeneratedTest{
			{
				Repo:        "xworkmate.svc.plus",
				Name:        fmt.Sprintf("%s-flutter-patrol-system", label),
				Description: fmt.Sprintf("Generate Flutter Patrol tests for %s. %s", label, context),
				Layer:       "patrol",
				TargetPaths: []string{"patrol_test/**/*_test.dart"},
				Inputs:      []string{"原生窗口/权限/系统弹窗/外链或 WebView 场景"},
				Assertions:  []string{"至少一个系统级真实设备行为被覆盖"},
				Environment: []string{"需要支持 Patrol 的 runner 或本地设备"},
			},
		},
	}
}

func recommendationsForTask(task protocol.TaskSummary) []protocol.Recommendation {
	switch task.MCP {
	case "frontend-mcp", "flutter-widget-mcp", "flutter-golden-mcp":
		return []protocol.Recommendation{
			{
				Title:                "Flutter UI regression triage",
				SuspectedLayer:       "flutter-ui",
				FailingContract:      task.MCP,
				LikelyFiles:          []string{"test/widget/", "test/golden/", "test/helpers/"},
				RecommendedTestFirst: "补一条最小 widget/golden 回归测试后再修复 UI 行为",
				SafeFixOrder:         []string{"确认 selector/key 未漂移", "确认 fixture 与 mock service", "再调整视觉或状态逻辑"},
				Summary:              "Inspect Flutter selectors, fixture wiring, and UI hydration before retrying the UI layer.",
			},
		}
	case "api-mcp", "api-contract-mcp", "go-unit-mcp":
		return []protocol.Recommendation{
			{
				Title:                "Go API contract drift",
				SuspectedLayer:       "go-api",
				FailingContract:      task.MCP,
				LikelyFiles:          []string{"internal/handler/", "internal/service/", "internal/repository/", "test/integration/"},
				RecommendedTestFirst: "先补 API contract 或 handler 回归测试，再修复状态码/响应体/鉴权分支",
				SafeFixOrder:         []string{"确认请求/响应契约", "确认 auth header 与 session/token", "确认 service/repository fixture"},
				Summary:              "Review API contract drift and auth headers, then add a regression test before merging.",
			},
		}
	case "db-mcp":
		return []protocol.Recommendation{
			{
				Title:                "Database fixture or schema mismatch",
				SuspectedLayer:       "database",
				FailingContract:      task.MCP,
				LikelyFiles:          []string{"test/integration/", "internal/repository/", "db fixtures"},
				RecommendedTestFirst: "补数据库集成回归测试，锁定 seed data 与 query contract",
				SafeFixOrder:         []string{"确认 schema 假设", "确认 fixture 状态", "确认回滚安全"},
				Summary:              "Check schema assumptions, fixture state, and rollback safety before retrying the database suite.",
			},
		}
	case "e2e-mcp", "desktop-e2e-mcp", "flutter-integration-mcp", "flutter-patrol-mcp":
		return []protocol.Recommendation{
			{
				Title:                "Critical path integration failure",
				SuspectedLayer:       "cross-repo-critical-path",
				FailingContract:      task.MCP,
				LikelyFiles:          []string{"integration_test/", "patrol_test/", "accounts API contract", "desktop bootstrap"},
				RecommendedTestFirst: "先补最小 integration/e2e 回归用例，锁定首个失败依赖",
				SafeFixOrder:         []string{"定位首个失败关键依赖", "验证 accounts 认证契约", "再验证 desktop 导航与设置流程"},
				Summary:              "Trace upstream dependencies and isolate the first failing critical path before rerunning e2e.",
			},
		}
	case "load-mcp":
		return []protocol.Recommendation{
			{
				Title:                "Load regression before promotion",
				SuspectedLayer:       "release-load",
				FailingContract:      task.MCP,
				RecommendedTestFirst: "先确认 e2e 通过，再降低并发定位阈值回归",
				SafeFixOrder:         []string{"确认 release e2e", "检查阈值/并发", "再评估是否允许推广"},
				Summary:              "Reduce concurrency and inspect threshold regressions before promoting the release candidate.",
			},
		}
	default:
		return []protocol.Recommendation{
			{
				Title:                fmt.Sprintf("Investigate %s failure", task.MCP),
				SuspectedLayer:       "unknown",
				FailingContract:      task.MCP,
				RecommendedTestFirst: "先生成一条定向回归测试，再回看失败日志",
				SafeFixOrder:         []string{"查看日志", "补回归测试", "修复后重跑"},
				Summary:              fmt.Sprintf("Review %s logs and generate a targeted regression test before retrying.", task.MCP),
			},
		}
	}
}
