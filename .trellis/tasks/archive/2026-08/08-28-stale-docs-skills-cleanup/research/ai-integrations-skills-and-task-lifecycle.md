# Research: AI Integrations, Skills, And Task Lifecycle Cleanup

- Query: Audit Codex, Claude Code, Pi, shared/project skills, Trellis-generated files, symlinks, hooks, backup artifacts, and active/completed task directories; classify each as keep, delete, normalize, or archive.
- Scope: internal
- Date: 2026-08-28

## Findings

### Executive Classification

| Classification | Exact targets | Evidence-based action |
| --- | --- | --- |
| KEEP | `.codex/**`, `.claude/**`, `.pi/**` | All three platform integrations are installed and wired according to their different Trellis lifecycle models. Do not delete or collapse them. |
| KEEP | `.agents/skills/**`, `.claude/skills/**` | Trellis workflow/bundled skills, the Mica project skill, and every macOS skill symlink are valid. Platform duplication is intentional. |
| KEEP | `.codex/hooks/session-start.py` | It is intentionally present but unregistered. Codex uses `UserPromptSubmit` plus `SubagentStart`; the per-prompt hook provides the one-shot bootstrap direction. |
| KEEP | `.trellis/scripts/hooks/linear_sync.py` | It is currently inactive, but it is an unchanged Trellis-managed optional lifecycle hook, not abandoned project code. |
| KEEP | `.trellis/.runtime/**`, `.trellis/workspace/**`, `.trellis/tasks/archive/**` | Runtime state is ignored and Trellis-owned; journals and archived tasks are durable history. None is a docs/skills cleanup target. |
| NORMALIZE LATER, NOT DELETE | `.agents/skills/trellis-channel/references/command-reference.md`, `.agents/skills/trellis-meta/references/local-architecture/workspace-memory.md` | `trellis update --dry-run` reports only these two files as user-modified. Diffs against the Claude copies are whitespace-only. The current task's integration preservation fence says to leave `.agents/skills` read-only. |
| ARCHIVE | `08-16-global-functional-audit`, `08-16-post-refactor-integration-audit`, then `08-16-dashboard-visual-hover-details` | All three metadata records are completed and the parent acceptance criteria are complete. Use `task.py archive --no-commit`; do not delete their contents. |
| KEEP ACTIVE | `08-04-workbench-native-ui-system`, `08-23-overview-flow-ribbons`, `08-28-stale-docs-skills-cleanup` | The first two still have explicit acceptance work; the last is the current planning task. |
| DELETE | None in this research scope | No obsolete integration, hook, skill, symlink, backup, reject, or task-history artifact was proven deletable. |

### Files Found And Their Roles

| Path | Role |
| --- | --- |
| `.codex/hooks.json` | Registers Codex per-prompt workflow state and native Trellis subagent context injection. |
| `.codex/hooks/{inject-workflow-state.py,inject-subagent-context.py,session-start.py}` | Trellis Codex hook implementations; SessionStart remains a retained template even though it is not registered. |
| `.codex/agents/trellis-{research,implement,check}.toml` | Native Codex subagent role definitions. |
| `.codex/config.toml` | Project document fallback, Apple docs MCP, hook-enablement notes, and native subagent depth. |
| `.claude/settings.json` | Registers Claude SessionStart, per-prompt state, and Task/Agent context hooks. |
| `.claude/hooks/*.py` | All three registered Claude hook implementations. |
| `.claude/agents/trellis-{research,implement,check}.md` | Claude subagent definitions. |
| `.claude/commands/trellis/{continue,finish-work}.md` | Explicit Claude workflow commands. |
| `.claude/settings.local.json` | Ignored user-local Swift LSP plugin enablement; it is not a repository cleanup target. |
| `.pi/settings.json` | Loads the Trellis extension and prompt directory. |
| `.pi/extensions/trellis/index.ts` | Pi session lifecycle, shell session bridge, context updates, and native `trellis_subagent` tool. |
| `.pi/agents/trellis-{research,implement,check}.md` | Pull-based Pi subagent definitions. |
| `.pi/prompts/trellis-{start,continue,finish-work}.md` | Pi workflow entry prompts; `trellis-start` is the manual SessionStart equivalent. |
| `.agents/skills/mica-controller-development/**` | Project-specific Mica architecture/controller/workflow constraints required by `AGENTS.md`. |
| `.agents/skills/trellis-*/**` | Shared Trellis workflow and bundled skills used by Codex and Pi. |
| `.claude/skills/trellis-*/**` | Claude's platform-rooted Trellis copies; they are expected generated files, not accidental duplicates. |
| `.agents/skills/{apple-hig-expert,macos-*,swift-*}` | Eleven resolving macOS/Swift skill links to the local AI toolbox. |
| `.claude/skills/{apple-hig-expert,macos-app-design,macos-development,mica-controller-development,swift-charts,swiftui-liquid-glass}` | Six resolving relative links into the shared skill layer. |
| `.trellis/.template-hashes.json` | Trellis template-management state; never hand-edit for cleanup. |
| `.trellis/scripts/hooks/linear_sync.py` | Optional Linear lifecycle adapter, inactive unless configured under lifecycle hooks. |
| `.trellis/.runtime/**` | Ignored session pointers and update-check throttle markers. |
| `.trellis/tasks/archive/**` | Twenty-one completed task directories: two under `2026-07` and nineteen under `2026-08`. |

### Codex: Keep The Current Default

- `.codex/hooks.json:2-25` registers only `UserPromptSubmit` and `SubagentStart`. The subagent matcher is restricted to the three Trellis agents at lines 14-23.
- `.codex/hooks/inject-workflow-state.py:68-73` explicitly says Codex does not receive the full SessionStart overview and instead points the main session to `trellis-start` once.
- `.codex/hooks/session-start.py:1-8` is a complete SessionStart implementation, but absence from `.codex/hooks.json` is deliberate under the established project decision. File presence alone is not evidence of dead code.
- `.codex/config.toml:20-26` documents the two user-side activation gates: hooks must be enabled in user config and approved in the `/hooks` UI. Project cleanup must not attempt to compensate by adding another registration.
- `.codex/config.toml:38-41` keeps native Trellis agents at one recursion level. The three TOML role files are therefore live integration inputs, not redundant prose.

Classification: keep every tracked `.codex` file unchanged, including the unregistered SessionStart template.

### Claude Code: Keep Registered SessionStart And Hook Chain

- `.claude/settings.json:9-40` registers `session-start.py` for `startup`, `clear`, and `compact`.
- `.claude/settings.json:41-62` registers subagent context injection for both `Task` and `Agent` tool names.
- `.claude/settings.json:63-73` registers per-prompt workflow-state injection.
- `.claude/settings.local.json:1-5` only enables the local Swift LSP plugin and is ignored by the user's global Git exclude. It is user-local state, not stale Trellis material.
- Claude's Trellis agent, command, hook, and skill files all have corresponding active settings or documented workflow entry points.

Classification: keep `.claude/**`. The empty ignored `.claude/worktrees/` directory has no tracked artifact to clean and should be left to Claude's runtime.

### Pi: Keep Extension-Based Lifecycle

- `.pi/settings.json:1-8` enables skill commands, loads `./extensions/trellis/index.ts`, and exposes `./prompts`.
- `.pi/extensions/trellis/index.ts:1736-1751` registers the native `trellis_subagent` tool and Trellis agent selector.
- `.pi/extensions/trellis/index.ts:1893-1900` handles `session_start` by establishing the context key and directing the user to `/trellis-start` or `/trellis-continue`.
- `.pi/extensions/trellis/index.ts:1905-1915` bridges the Trellis context ID into shell commands.
- `.pi/extensions/trellis/index.ts:1932-1965` handles `before_agent_start`, snapshots task context, and publishes later on-disk updates.
- `.pi/prompts/trellis-start.md:1-34` identifies the prompt as the manual session bootstrap for a platform without a Python SessionStart hook. This is complementary to the extension, not a missing integration.

Classification: keep all tracked `.pi` agents, prompts, settings, and extension files.

### Skills And Symlinks

- Shared skill inventory contains twelve Trellis skills, one project-specific Mica skill, and eleven macOS/Swift symlinks.
- Claude contains nine generated Trellis skill directories plus six relative symlinks to project/shared skills. The different count is platform design: continue/finish are commands in Claude and start is supplied by Claude's registered SessionStart behavior.
- `AGENTS.md:6` requires `mica-controller-development`; `AGENTS.md:15` requires `macos-app-design`, `apple-hig-expert`, and `swiftui-liquid-glass` for UI work. `docs/DEVELOPMENT.md:15` invokes the Apple HIG checker through the skill path.
- `find -L .agents/skills .claude/skills -maxdepth 1 -type l` returned no broken links.
- All eleven `.agents/skills` macOS/Swift links resolve to `/Users/garland/Library/Application Support/com.ai-toolbox/skills/...` on this machine. All six `.claude/skills` links resolve relatively through `.agents/skills`.
- Three absolute toolbox links are tracked: `macos-auto-update`, `macos-release`, and `swift-testing-expert`; the other eight are local/untracked. This is a portability caveat, not evidence that the skills are obsolete.

Classification: keep every current skill and symlink. Do not collapse `.claude/skills/trellis-*` into `.agents/skills`; Trellis ships platform-rooted copies intentionally.

### Trellis Generated Files And Drift

- Local project and CLI versions are both `0.6.15` (`.trellis/.version:1`; `trellis --version`).
- `trellis update --dry-run` reported 82 unchanged files (`5` shown plus `77 more`) and only two user-modified files. It made no changes.
- The `command-reference.md` difference is only removal of one final blank line after line 479.
- The `workspace-memory.md` difference is only removal of Markdown hard-break trailing spaces on two lines around line 56.
- These differences have no trigger, content, or runtime effect. Under this task's read-only integration fence, leave them as-is; a future explicit template-normalization task may restore exact bytes.
- `.trellis/scripts/hooks/linear_sync.py:1-27` documents an optional `linearis` integration. `.trellis/config.yaml:35-51` has no active lifecycle hooks, so the script is inert today. `.trellis/.template-hashes.json:49` records it as managed and the dry-run classifies it unchanged. Do not delete it merely because it is disabled.
- JSON parsing passed for `.codex/hooks.json`, `.claude/settings.json`, `.claude/settings.local.json`, `.pi/settings.json`, and `.trellis/.template-hashes.json`.

Classification: no generated Trellis file is deletable. Keep the two whitespace drift files unless the parent task intentionally changes its preservation fence.

### Backup, Reject, Cache, And Runtime Artifacts

- No `*.bak`, `*.backup`, `*.old`, `*.orig`, `*.rej`, `*.new`, editor-swap, `*.pyc`, or `.DS_Store` artifact was found outside excluded Git/tmp paths.
- `.trellis/.gitignore:7-8` identifies `.runtime/` as session/window state; `.trellis/.gitignore:24-28` also reserves Trellis backup/conflict artifacts.
- `.trellis/.runtime/` currently contains 80 ignored update-check marker files and two active session JSON files. The markers throttle update notices and session JSON selects current tasks. The Trellis generated-files contract says runtime state is not a manual-edit surface.
- `.trellis/workspace/` contains its index, developer index, and journal. It is durable session history explicitly protected by the approved scope.

Classification: no backup artifact requires deletion. Exclude ignored runtime state and workspace history from this cleanup.

### Task Directory Classification

Archive, in this order:

1. `.trellis/tasks/08-16-global-functional-audit`
2. `.trellis/tasks/08-16-post-refactor-integration-audit`
3. `.trellis/tasks/08-16-dashboard-visual-hover-details`

Evidence:

- Each child has `status: completed` and `completedAt: 2026-08-16` at its `task.json:6-14`; each points to the dashboard parent at line 22.
- The parent has `status: completed` and `completedAt: 2026-08-16` at `task.json:6-14`, retains both child names at lines 21-24, and records the final 305-test verification at line 27.
- The parent PRD marks all eighteen acceptance criteria complete at `prd.md:219-262`.
- The baseline audit report records 316 passing tests and local-only checks at `audit-report.md:32-46`, reports every coverage row terminal at lines 48-82, and states no unresolved Critical/High/Medium issue remains at lines 84-86 and 150-155.
- The baseline child's own PRD checkboxes remain unchecked even though its metadata and final report say complete. Archival preserves this historical discrepancy; deleting or silently rewriting it would lose evidence.

Use the child-first order from the active task design. `.trellis/scripts/common/task_store.py:576-593` clears active children's `parent` field when archiving a parent. `.trellis/scripts/common/task_utils.py:100-123` only finds direct active task directories, so archiving children first means the later parent archive cannot erase the archived child-to-parent pointers. This preserves both directions of the historical relationship. Use `--no-commit` so the main session controls the final task-scoped commit.

Keep active:

- `.trellis/tasks/08-04-workbench-native-ui-system/task.json:6-14` remains `in_progress`; `implement.md:101-111` leaves cross-surface, lifecycle, performance, documentation, and real-controller user acceptance unchecked.
- `.trellis/tasks/08-23-overview-flow-ribbons/task.json:6-14` remains `in_progress`; `implement.md:23-28` leaves light/dark user visual acceptance and archival unchecked.
- `.trellis/tasks/08-28-stale-docs-skills-cleanup` is the current planning task and must not be archived by the implementation step.

Existing archives contain twenty-one completed task directories. They are already in the correct lifecycle location and must not be deleted.

## External References

- Trellis CLI/project version: `0.6.15`, verified locally with `trellis --version` and `.trellis/.version`.
- `trellis update --dry-run` could not fetch the latest npm version in the restricted environment, but local project/CLI parity and template drift scanning completed successfully.
- No external web source was needed. Local Trellis files and the installed CLI are authoritative for this project integration audit.

## Related Specs And Task Contracts

- `AGENTS.md:4-24` - project authority order, required Mica/macOS skills, runtime safety, and durable documentation entry points.
- `.trellis/workflow.md:35-65` - task lifecycle and archive commands.
- `.trellis/workflow.md:154-169` - in-progress subagent dispatch flow.
- `.agents/skills/trellis-meta/references/local-architecture/generated-files.md` - template hashes, generated platform files, and runtime-state editing boundary.
- `.agents/skills/trellis-meta/references/local-architecture/context-injection.md` - SessionStart, workflow-state, and subagent injection models.
- `.agents/skills/trellis-meta/references/local-architecture/task-system.md` - task artifacts, archive retention, and parent/child semantics.
- `.agents/skills/trellis-meta/references/platform-files/platform-map.md` - expected Codex, Claude Code, and Pi file roots.
- `.trellis/tasks/08-28-stale-docs-skills-cleanup/prd.md` - approved preservation and archive requirements.
- `.trellis/tasks/08-28-stale-docs-skills-cleanup/design.md` - integration preservation fence and child-first archive design.

## Caveats / Not Found

- The current cleanup task was created concurrently and remains untracked while planning is in progress. This research file is the only path written by this agent.
- The two `trellis update` drift findings are harmless whitespace differences, but the dry run will continue to ask for a decision until exact template bytes are restored. The current approved design says not to edit `.agents/skills`, so this is a consciously retained warning.
- The three tracked absolute macOS skill symlinks resolve on this machine but are not portable to a checkout lacking the same `/Users/garland/Library/Application Support/com.ai-toolbox/skills` tree. Do not delete them in this cleanup; treat portability as a separate repository policy decision.
- The global functional audit PRD checkbox state disagrees with its completed metadata and final audit report. The final report is strong completion evidence, and archival is recoverable/history-preserving; the inconsistency should remain visible rather than be rewritten during cleanup.
- No stale or broken Codex/Claude/Pi hook target, agent definition, skill link, backup file, or rejected update sidecar was found.
