# OpenClaw 与 Claude Code 面试速记

最后核对时间：2026-03-23

这份笔记不是泛泛介绍，而是面向面试复述。重点是把几个容易混淆的概念拆开说清楚：

- OpenClaw 的技能系统、workspace 文件、Gateway、ClawHub、multi-agent
- Claude Code CLI、hooks、subagents
- 日常怎么用
- 常见坑和实现细节

## 一句话总览

我会把 OpenClaw 理解成一个“常驻 Gateway + agent workspace + skills + routing + memory + channels”的运行时系统。

- Gateway 是常驻控制面，负责路由、channel 连接、session、hook、RPC 和运维入口。
- workspace 是 agent 的人格与长期上下文落点，核心文件是 `AGENTS.md`、`SOUL.md`、`USER.md`、`IDENTITY.md`、`HEARTBEAT.md`、`MEMORY.md`。
- skills 是按 `SKILL.md` 组织的能力包，既能本地覆盖，也能通过 ClawHub 分发。
- multi-agent 不是“多 prompt”，而是每个 agent 都有独立 workspace、agentDir、auth profiles、session store，再通过 bindings 把不同 channel/account/peer 路由给不同 agent。
- Claude Code 相关能力要单独看：它自己的 hooks、subagents、settings 体系，和 OpenClaw 自己的 hooks/subagents 是两套机制。

## 先把几个核心对象分开

### 1. OpenClaw Gateway

Gateway 是 OpenClaw 的常驻服务，不只是一个聊天入口。

- 默认就是一个 always-on 进程，统一承接 WebSocket 控制/RPC、HTTP API、channel 连接、hooks、session 生命周期。
- 默认端口是 `18789`，默认 bind 是 `loopback`。
- 远程访问推荐走 SSH tunnel 或 tailnet，而不是直接裸暴露。

可以直接背的表达：

> OpenClaw 的核心不是单个 prompt，而是 Gateway 常驻进程。它持有 channel 连接、路由、session、hooks 和控制面。agent 只是 Gateway 里的某个 runtime 身份。

### 2. Agent workspace

workspace 是 agent 的“家”，也是 prompt bootstrap 的来源。

默认路径与关键目录：

```text
~/.openclaw/workspace
~/.openclaw/skills
~/.openclaw/agents/<agentId>/agent
~/.openclaw/agents/<agentId>/sessions
```

高频要点：

- workspace 是默认 cwd，但不是硬隔离；真隔离要开 sandbox。
- `~/.openclaw/` 里放配置、凭据、sessions，不应该和 workspace 混成一个概念。
- workspace 非常适合放 private git repo 做备份，但不要把 secrets 一起提交。

### 3. agentDir / auth / sessions

一个 agent 的“隔离”不仅是 prompt 文件，还包括：

- 独立 workspace
- 独立 `agentDir`
- 独立 auth profiles
- 独立 sessions

这是 multi-agent 真正成立的前提。

## Skills 系统怎么讲

OpenClaw 的 skills 基于 `SKILL.md`，兼容 AgentSkills 风格：目录里至少有一个 `SKILL.md`，前面是 YAML frontmatter，后面是具体说明。

### Skills 的来源和优先级

OpenClaw 会从三层加载 skills：

1. bundled skills
2. `~/.openclaw/skills`
3. `<workspace>/skills`

优先级是：

`<workspace>/skills` > `~/.openclaw/skills` > bundled

这点很重要，因为它直接决定了我平时的工作流：

- 先把 skill 放到当前 workspace 做最小验证
- 验证通过再决定要不要放到 `~/.openclaw/skills` 做机器级共享
- 想公开复用时再发到 ClawHub

### `SKILL.md` 的本质

`SKILL.md` 不是一个随便写的 prompt 文件，它是带 metadata 的能力描述。

常见字段：

- `name`
- `description`
- `metadata.openclaw.requires.*`
- `metadata.openclaw.install`
- `primaryEnv`

我会这样解释：

> `SKILL.md` 决定了这个技能叫什么、什么时候可用、依赖什么命令和环境变量、如何安装，以及模型什么时候该读这份说明。

### Gating 机制

skills 不是“目录里有就一定进 prompt”。OpenClaw 会做 load-time gating：

- `requires.bins`
- `requires.anyBins`
- `requires.env`
- `requires.config`
- `os`

也就是说，skill 是否可见，不只是看文件在不在，还取决于当前 host 环境、配置和二进制是否满足条件。

### ClawHub 是什么

ClawHub 是 OpenClaw 的 public skill registry，用来：

- 搜索技能
- 安装技能
- 更新技能
- 发布/备份技能

常用命令：

```bash
clawhub search "calendar"
clawhub install <skill-slug>
clawhub update --all
clawhub sync --all
```

我平时会把它当成“skill 包管理器 + 分发渠道”。

### Skills 相关面试坑

- 不要把 skills 说成只是 prompt 模板。它有发现、优先级、gating、安装和 registry。
- workspace skill 和 managed skill 不一样。前者是当前 agent 局部覆盖，后者是整台机器共享。
- 第三方 skill 要按不可信代码看待，尤其是会落到 host 环境变量和 shell 的。
- skill 在 host 上满足 `requires.bins`，不代表 sandbox 里也能跑；这在容器化场景很容易踩坑。

## Workspace 文件怎么讲

### 最重要的几个文件

- `AGENTS.md`：行为规则、工作方式、记忆策略
- `SOUL.md`：人格、语气、边界
- `USER.md`：用户画像和称呼方式
- `IDENTITY.md`：agent 自我身份
- `TOOLS.md`：本机工具和约定说明
- `HEARTBEAT.md`：心跳轮询时的极简 checklist
- `BOOTSTRAP.md`：新 workspace 的一次性引导
- `MEMORY.md`：长期记忆
- `memory/YYYY-MM-DD.md`：日记式日常记忆

### 它们和 prompt 的关系

这些文件不是“给人看的文档”而已，很多会直接进入系统 prompt 的 bootstrap context。

当前实现里，`loadWorkspaceBootstrapFiles()` 会读取：

- `AGENTS.md`
- `SOUL.md`
- `TOOLS.md`
- `IDENTITY.md`
- `USER.md`
- `HEARTBEAT.md`
- `BOOTSTRAP.md`
- `MEMORY.md` 或 `memory.md`（如果存在）

但有两个关键补充：

1. `memory/YYYY-MM-DD.md` 不会自动注入，主要通过 `memory_search` / `memory_get` 按需读。
2. bootstrap 文件是吃上下文窗口的，所以 `MEMORY.md` 写太大，会直接推高 token 和 compaction 频率。

### `SOUL.md`

`SOUL.md` 是人格边界层，适合放：

- 说话风格
- 外部动作的边界
- 对群聊、隐私、代发的态度

如果面试官问“为什么不是全写在 AGENTS.md 里”，我会答：

> 因为 SOUL 更像稳定人格边界，AGENTS 更像操作手册。一个管‘你是谁’，一个管‘你怎么工作’。

### `MEMORY.md`

`MEMORY.md` 是长期记忆，不应该写成流水账。

适合写：

- 用户偏好
- 长期项目上下文
- 稳定决策
- 反复踩过的坑

不适合写：

- 临时聊天碎片
- 大段日志
- 高频变化信息

### `HEARTBEAT.md`

`HEARTBEAT.md` 是给 heartbeat run 的短清单。

正确用法：

- 保持极短
- 放周期性检查项
- 用 heartbeat 批量处理低精度轮询任务

错误用法：

- 把它当完整 runbook
- 写成长篇 prompt
- 放太多会高频变化的细节

### 这里最值得说的实现细节

有一处很适合在面试里体现“我看过代码，不是只背文档”：

- 文档里常见说法是 subagent 只注入 `AGENTS.md` 和 `TOOLS.md`
- 但当前 `src/agents/workspace.ts` 的 `MINIMAL_BOOTSTRAP_ALLOWLIST` 实际还保留了 `SOUL.md`、`IDENTITY.md`、`USER.md`
- 它过滤掉的是 `HEARTBEAT.md`、`BOOTSTRAP.md`、`MEMORY.md`

这说明一个现实问题：文档和 runtime 细节可能漂移，答题时要强调“以当前版本代码为准”。

## Gateway 怎么讲

我会把 Gateway 讲成 OpenClaw 的 control plane：

- 常驻进程
- 对内负责 agent runtime、sessions、hooks、queue、routing
- 对外负责 channel 接入、RPC、HTTP API、远程访问

日常使用里我关心的不是“怎么启动一次”，而是：

- 它是否常驻
- 它的 auth 是否配置正确
- 它当前绑定到哪个 workspace / state dir
- `channels status --probe` 是否健康
- 远程是不是通过 tunnel/tailnet 连通

常见命令：

```bash
openclaw gateway
openclaw gateway status
openclaw gateway restart
openclaw channels status --probe
openclaw logs --follow
openclaw doctor
```

Gateway 相关面试坑：

- 不要把 Gateway 说成“websocket 聊天服务”这么窄，它其实是系统中枢。
- 多个 gateway 实例可以跑，但必须隔离 `port`、`config`、`state dir`、`workspace`。
- 远程接入优先 SSH tunnel / Tailscale，不建议无脑放公网。

## Multi-agent 怎么讲

multi-agent 的关键不是“支持多个名字”，而是隔离边界和路由规则。

### 一个 agent 到底隔离了什么

一个 agent 拥有自己的：

- workspace
- `agentDir`
- auth profiles
- session store
- skills 局部覆盖

对应路径通常是：

```text
~/.openclaw/agents/<agentId>/agent
~/.openclaw/agents/<agentId>/sessions
```

### 路由靠什么完成

靠 `bindings`。

可以按这些维度匹配：

- channel
- accountId
- peer
- guildId
- teamId

最容易踩坑的一条：

- 省略 `accountId` 只会匹配默认账号
- `accountId: "*"` 才是 channel-wide fallback

### 我会怎么描述日常使用

> 如果我要给不同人、不同项目、不同消息渠道配不同人格和上下文，我不会只改 prompt，而是直接建多个 agent。每个 agent 单独 workspace 和 auth，再用 bindings 把 Telegram/Discord/WhatsApp 的 account 或群路由过去。

### Multi-agent 的高频坑

- 千万别复用 `agentDir`，否则 auth/session 会串。
- 只建多个 workspace 不够，auth profiles 和 session store 也得隔离。
- account 级和 channel 级 binding 语义不同，省略 `accountId` 很容易误以为“全局都生效”。

## OpenClaw hooks 和 Claude Code hooks 不是一回事

这是面试里特别容易答混的点。

### OpenClaw hooks

OpenClaw hooks 是 Gateway 内部的事件自动化机制。

特点：

- 目录结构是 `HOOK.md` + `handler.ts`
- 来源分为 workspace / managed / bundled
- 运行在 Gateway 生命周期内
- 典型事件包括 command、session、agent、gateway、message

bundled hooks 里比较典型的有：

- `session-memory`
- `bootstrap-extra-files`
- `command-logger`
- `boot-md`

我会把它理解为：

> OpenClaw hooks 更像 Gateway 内部的插件式自动化，可以改 bootstrap、写 memory、记录命令、在启动时跑 `BOOT.md`。

### Claude Code hooks

Claude Code hooks 是 Claude Code 自己的 hooks 体系，配置位置主要有：

- `~/.claude/settings.json`
- `.claude/settings.json`
- `.claude/settings.local.json`

另外，官方也支持把 hooks 放进 skill 或 agent frontmatter，在对应 skill/agent 激活时生效。

官方支持的 hook 类型包括：

- `command`
- `prompt`
- `agent`
- `http`

常见事件包括：

- `PreToolUse`
- `PostToolUse`
- `Notification`
- `SessionStart`
- `ConfigChange`
- `SubagentStart`
- `SubagentStop`

我会这样区分：

> Claude Code hooks 是围绕 Claude Code 自己的 tool lifecycle 做自动化和策略控制，比如自动格式化、阻止改受保护文件、session compact 后重新注入上下文。OpenClaw hooks 则是 Gateway 侧的事件机制。

### Claude Code hooks 的高频坑

- `PermissionRequest` 在 `-p` 非交互模式下不会触发，自动化场景要改用 `PreToolUse`。
- hook 脚本 stdout/stderr/exit code 很关键；shell profile 里有无条件 `echo` 会把 JSON 输出污染掉。
- `/hooks` 是查看器，不是编辑器。
- JSON 改了如果 watcher 没吃到，要重启 session。

## Claude Code subagents 怎么讲

Claude Code 的 subagents 是原生的“上下文隔离助手”。

### 它们的特点

- 每个 subagent 有自己的 context window
- 可以限制工具
- 可以指定 model
- 可以指定 `permissionMode`
- 可以带 `hooks`、`skills`、`memory`
- 可以选 `isolation: worktree`

定义位置有优先级：

1. `--agents` CLI flag
2. `.claude/agents/`
3. `~/.claude/agents/`
4. plugin 的 `agents/`

内置常见 agent：

- Explore
- Plan
- General-purpose

### Claude Code subagents 最容易答错的地方

- Claude Code subagents 不会继续 spawn subagents，官方文档明确说了不能无限嵌套。
- plugin subagents 不支持 `hooks`、`mcpServers`、`permissionMode` 这些字段。
- 手工加 agent 文件后，通常要重启 session 或用 `/agents` 让它立刻生效。

## OpenClaw subagents 又是什么

OpenClaw 自己也有 subagents，但概念完全不同。

它是 native delegated runtime：

- 真的有独立 session key
- 可以后台运行
- 完成后 announce 回主会话
- 默认 session key 形如 `agent:<agentId>:subagent:<uuid>`

而且 OpenClaw 支持配置嵌套深度：

- 默认只允许一层
- 配置 `maxSpawnDepth: 2` 可以做 orchestrator -> worker

所以我会明确区分：

> Claude Code subagents 更像同一会话里的专职助手；OpenClaw subagents 是 Gateway 内部有独立 session 生命周期的委派运行。

## Claude Code CLI 在 OpenClaw 里怎么用

这个点也值得拆开讲，因为 OpenClaw 对 Claude Code CLI 至少有三种关系。

### 1. 作为 CLI backend fallback

OpenClaw 可以直接把 Claude Code CLI 当成本地 CLI backend。

比如：

```bash
openclaw agent --message "hi" --model claude-cli/opus-4.6
```

当前默认参数是：

```text
claude -p --output-format json --permission-mode bypassPermissions
```

这条路径的性质是：

- text-only fallback
- OpenClaw tools 不可用
- session continuity 可保留
- 更像兜底 runtime，不是主力 agent runtime

### 2. 作为 ACP harness

OpenClaw 还可以把 Claude Code 作为 ACP runtime 的外部 harness。

这时它不是 native subagent，而是：

- `runtime: "acp"`
- session key 形如 `agent:<agentId>:acp:<uuid>`
- 用 `/acp ...` 或 `sessions_spawn(runtime:"acp")`

这条路径更适合“在某个 thread 里开一个持续的 Claude Code coding session”。

### 3. 作为 setup-token 工具

Anthropic 侧常见还有：

```bash
claude setup-token
```

OpenClaw 文档里也把 Claude Code CLI 当作 Anthropic setup-token 的来源之一。

## 我日常会怎么用

如果要用一句顺口的话概括：

> 我会把 OpenClaw 当成长期常驻的大脑和调度层，把 Claude Code 当成本地 coding harness 和 repo 内自动化工具。

更具体一点：

1. OpenClaw 侧
   - Gateway 常驻在固定 host 上
   - workspace 里维护 `AGENTS.md` / `SOUL.md` / `MEMORY.md`
   - 周期性检查交给 `HEARTBEAT.md` + heartbeat
   - 精确定时和隔离任务交给 cron
   - 新能力先在 `<workspace>/skills` 验证，再决定是否推到 ClawHub
   - 多 persona / 多渠道就走 `agents add` + `bindings`

2. Claude Code 侧
   - repo 内用 `.claude/settings.json` 放 project hooks
   - 用 `PreToolUse` / `PostToolUse` 做保护和格式化
   - 用 `/agents` 或 `.claude/agents/` 配自定义 subagent
   - 复杂任务拆给只读 Explore 或专门 reviewer/debugger

## 我会主动提到的常见坑

- `MEMORY.md` 写太大，会直接拖高 token 消耗和 compaction 频率。
- `memory/YYYY-MM-DD.md` 是日记，不该拿来替代 `MEMORY.md`。
- `HEARTBEAT.md` 应该很短；太长就把 heartbeat 变成高成本 prompt。
- OpenClaw 文档和当前实现可能漂移，尤其是 bootstrap 注入和 subagent 上下文裁剪，答题时最好说“以当前代码为准”。
- multi-agent 千万别复用 `agentDir`，否则 auth 和 sessions 容易串。
- 省略 `accountId` 不是“匹配全部账号”，只是默认账号。
- OpenClaw CLI backend 和 OpenClaw native runtime 不是一回事；CLI backend 默认没有 OpenClaw tools。
- Claude Code 的 `PermissionRequest` hooks 在 `-p` 下不触发，自动审批逻辑要放到 `PreToolUse`。
- shell profile 里无条件 `echo` 会搞坏 Claude Code hook 的 JSON 输出。
- 手工创建 Claude Code subagent 文件之后，如果没 reload session，看起来就像“配置没生效”。

## 60 秒答法

如果面试官让我用一分钟讲清楚，我会这么答：

> OpenClaw 我理解成一个 Gateway 驱动的 agent runtime 平台。Gateway 常驻，负责 channel 接入、session、routing、hooks 和控制面；workspace 里用 `AGENTS.md`、`SOUL.md`、`USER.md`、`IDENTITY.md`、`HEARTBEAT.md`、`MEMORY.md` 来定义人格、行为和长期记忆。skills 是基于 `SKILL.md` 的能力包，有 bundled、managed、workspace 三层优先级，也可以通过 ClawHub 分发。multi-agent 不是多 prompt，而是每个 agent 都有独立 workspace、auth、session store，再靠 bindings 路由不同 channel/account/peer。Claude Code 那边我会分开讲：它自己的 hooks 是配置在 `settings.json` 里的生命周期自动化，subagents 是单会话内的隔离助手；而 OpenClaw 也有自己的 hooks 和 subagents，但那是 Gateway runtime 里的另一套机制。日常上，我会让 OpenClaw 常驻做长期上下文和消息路由，Claude Code 用来做 repo 内 coding 和自动化。最容易踩坑的是把这两套 subagent/hook 体系混在一起，以及让 `MEMORY.md`、`HEARTBEAT.md` 长到失控。 

## 建议顺手再准备的追问

- 为什么 `SOUL.md` 和 `AGENTS.md` 要分开？
- `MEMORY.md` 和 daily memory 怎么分层？
- heartbeat 和 cron 什么时候分别用？
- OpenClaw subagent 和 Claude Code subagent 的最大区别是什么？
- 为什么 multi-agent 一定要隔离 `agentDir`？
- skill 为什么要有 gating，而不是一股脑全加载？

## 主要依据

OpenClaw 本地资料：

- `docs/tools/skills.md`
- `docs/tools/clawhub.md`
- `docs/concepts/agent-workspace.md`
- `docs/concepts/memory.md`
- `docs/concepts/multi-agent.md`
- `docs/tools/subagents.md`
- `docs/tools/acp-agents.md`
- `docs/gateway/index.md`
- `docs/gateway/cli-backends.md`
- `docs/automation/hooks.md`
- `src/agents/workspace.ts`
- `src/agents/bootstrap-files.ts`
- `src/agents/cli-backends.ts`

Claude Code 官方资料：

- https://code.claude.com/docs/en/hooks-guide
- https://code.claude.com/docs/en/sub-agents
