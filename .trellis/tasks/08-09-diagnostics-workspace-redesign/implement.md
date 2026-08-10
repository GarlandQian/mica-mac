# 诊断与操作工作台联动重构实施计划

## Implementation Status

- Product implementation is complete through Phase 7, including focused and full verification.
- `trellis-check` and the durable spec pass are complete. The Stash/Mihomo DNS dispatcher boundary is recorded in the Workbench UI contract.
- Verified on 2026-08-09: `swift build`, 307-test full suite, focused Actions/Diagnostics and endpoint suites, source contract, localization JSON, `git diff --check`, and task context validation all pass.
- Runtime smoke and real-controller contact were intentionally not run. `tmp/codex/swift-build` remains as reusable build cache.
- On 2026-08-10 the user adopted and authorized the post-implementation correctness audit plus measured full-Workbench performance scope. Correctness fixes and the measured product optimization pass are implemented.
- Full-Workbench before/after reports now cover the real high-cardinality projection boundaries. Connection row/cache/search and shared data-browser search changes crossed the repeated 10% retention threshold; rejected alternatives were removed.
- Verified on 2026-08-10: focused 37-test projection suite, `swift build`, 313-test full suite, source contract, localization JSON, four-report fidelity/threshold comparison, `git diff --check`, and task validation all pass.
- Staging, commit, archival, and runtime smoke remain intentionally deferred because the working tree contains overlapping pre-existing work and this audit must not contact a controller or launch Mica.

## Execution Rules

- 当前是 Codex inline 流程。当前 task 已是 `in_progress`；只有用户明确批准本轮最终规划摘要后，才加载 `trellis-before-dev` 并进入产品编辑，不重复启动 task，除非 Trellis 状态检查明确要求。
- 以当前 dirty worktree 为基线。Diagnostics、Actions、RouterEditor 和共享 Workbench 文件目前包含既有未提交/未跟踪工作；实现前记录精确状态，不回退或覆盖其他用户修改。
- 主会话直接实施和检查，不派发 implement/check sub-agent。
- 先完成全部相关修改，再集中验证；失败后只重跑受影响检查。
- 不启动 Mica、不连接真实 controller、不执行 runtime smoke 或远端动作。临时输出放在 `tmp/codex/` 并在结束时清理。
- 不增加 package，不降低 Swift tools/macOS target，不改 controller API、credential store 或 report redaction boundary。

## Phase 1. Baseline And Contract Audit

- [ ] 运行 `git status --short` 并记录所有任务相关文件的 tracked/untracked 状态，区分已有修改与本任务增量。
- [ ] 重新读取 PRD、design、issue/actions research、`mica-controller-development` 与相关 frontend/live-session specs。
- [ ] 复核 `controllerSessionPresentation -> controllerHealth/snapshot/capabilities -> Diagnostics/Actions` 数据流，以及 Workspace destination/editor intent、真实 operation dispatchers 和 toolbar session controls。
- [ ] 为 Auto Detect、mihomo/Nikki/OpenClash、CMFA、Stash、sing-box、Surge、unknown/unsupported 记录 capability -> readiness -> dispatcher -> visible command 基线，确认没有 capability-only 按钮。
- [ ] 复核现有 diagnostics export/redaction tests，确定它们是不变量而不是 UI 重构目标。

回退点：本阶段只读，不修改应用源码。

## Phase 2. Pure Diagnostics And Actions Projections

- [ ] 在 `WorkbenchDiagnosticsPresentation.swift` 中以纯值类型建立 Diagnostics input、overall state、freshness、issue、evidence、area、technical group 和 typed action。
- [ ] 实现 controller access、adapter、stale/failed retained data、paused、partial、endpoint/data-domain 和 live telemetry 的固定优先级。
- [ ] 实现 capability-aware suppression 与根因去重；禁止使用本地化字符串、时间戳或数组索引作为 issue ID。
- [ ] 实现 Available Now 与 technical groups；不读取 raw payload、command log 或 report body。
- [ ] 实现 selected issue reconciliation helper：preserve、resolve-to-first、controller/generation reset 和 healthy clear。
- [ ] 删除旧 SwiftUI 可见 projection 对 endpoint steps/check results/capability/coverage/observability 八组列表的依赖；底层 AppModel 模型保持可供其他消费者使用。
- [ ] 新建 `WorkbenchActionsPresentation.swift`，建立 availability、target scope、recovery、command group/risk/intent 和 executable inventory 纯模型。
- [ ] 以 session readiness + capability + operation row + adapter-appropriate dispatcher 交集生成 Actions 命令；数量只统计当前可执行命令。
- [ ] 覆盖全 controller family；显式压制 sing-box memory -> Mihomo command 等 capability/status 与 dispatcher 不匹配项。
- [ ] 建立 factual controller target scope：This Mac、Network Host、Unconfigured；显式 mac-local 允许 loopback，router-bound failure 给出 typed recovery evidence。

回退点：两套投影均可独立于 SwiftUI 编译和测试；若模型不满足 typed evidence/dispatcher proof，省略问题或命令，不引入字符串猜测或推测能力。

## Phase 3. Root Intents And Shared Wiring

- [ ] 修改 `WorkbenchWorkspaceView`，向 Diagnostics 与 Actions 传入 destination binding 与现有 `onEditController`。
- [ ] 在 Diagnostics root 构造低频 input，生成 snapshot，并只观察 lifecycle/health/capability/metadata 必需字段。
- [ ] 建立 typed action router：Refresh、Resume、Edit Controller、Navigate；Copy Report 保持单独支持命令。
- [ ] 对 controller ID、generation 和 issue 集合变化做稳定 selection reconciliation。
- [ ] 在 Actions root 建立 typed intent router，复用现有 Test/Refresh/direct/runtime operations、同窗口 Edit 和 Open Diagnostics；投影不接收 closures。
- [ ] controller ID、generation、availability 或 visible operation 变化时清除 Actions pending confirmation。
- [ ] 在 `WorkbenchChrome` 中只对 Diagnostics 隐藏 Test，保留 Refresh 作为唯一 Recheck 入口和全局 Pause/Resume；其他目的地不变。

回退点：Workspace pass-through、toolbar condition 和 Diagnostics root 分开修改，可逐片恢复而不影响 projection。

## Phase 4. Adaptive All-Controller Actions UI

- [ ] 替换单一 grouped-form 构图：checking/recovery 使用紧凑状态与 Test/Edit/Diagnostics intents；不显示 disabled Refresh、空 sections 或误导数量。
- [ ] ready/partial 使用一个 outer ScrollView；宽屏将真实 command groups 排为两个扁平列，窄屏复用同组顺序单列。
- [ ] 把 lifecycle/destructive commands 放在独立全宽末区，保留现有内联确认、role 和 generation safety。
- [ ] controller 只有少量 standalone commands 时显示紧凑 related-workspaces 导航，不复制各职责页操作，也不填充虚构命令。
- [ ] command bar 以 controller/session availability 为主；可执行数量只作为准确次级信息。
- [ ] 在 Actions recovery、Diagnostics evidence 和 RouterEditor diagnosis 复用 target-scope presentation；只提示，不自动修改 profile 或远端配置。
- [ ] 确保每个 controller snapshot 的命令按钮调用正确 adapter dispatcher；unresolved/unsupported 不生成 disabled command wall。

回退点：先切换 truthful projection/recovery state，再启用双栏；若宽屏布局回归，保留新模型与单栏 composition。

## Phase 5. Adaptive Diagnostics UI

- [ ] 用全宽、单一 ScrollView 的 Diagnostics canvas 替换 1180pt management canvas。
- [ ] 构建 unframed verdict header，显示 controller、overall state、freshness、last success/check time；checking 使用原生 ProgressView。
- [ ] 构建宽屏问题列表 + 选中详情，保持 320-380pt master 和 flexible detail；使用一个稳定 separator，不套卡片。
- [ ] 构建窄屏同列表行内详情，复用同一 selected issue ID，不创建第二展开集合或嵌套滚动。
- [ ] 构建健康态单栏摘要与 Available Now 平面 icon/value grid；省略不支持域和绿色成功清单。
- [ ] 构建单一 Technical Details disclosure 与一个 Copy Report command，移除 Copy Endpoint/Check 顶层命令和旧八组 outline。
- [ ] 为 issue rows 增加全行 Button、selected trait、方向键移动、VoiceOver 合并与 Reduce Motion 降级。
- [ ] 确保长英文/中文/controller 名称/error detail 在四档字号和窄窗口下换行，不产生横向滚动或按钮文字截断。

回退点：先完成 compact composition，再启用 wide master-detail；若 split 有问题，保留新投影和 compact UI，不恢复旧内容模型。

## Phase 6. Localization, Tests And Source Contracts

- [ ] 在 `Localizable.xcstrings` 中补齐 Diagnostics/Actions/target-scope 新文案的 English/Simplified Chinese，删除只在旧可见 UI 使用且确认无其他消费者的文案时保持谨慎。
- [ ] 更新/新增 focused Diagnostics projection tests，覆盖 checking、blocked、stale retained、paused、dedup、unsupported suppression、endpoint mapping、Available Now 和 selection reconciliation。
- [ ] 更新/新增 focused Actions projection tests，覆盖 availability precedence、准确 executable count、全部 controller inventories、stable order、dispatcher suppression、loopback/mac-local target scope 和 confirmation invalidation。
- [ ] 保留 export credential/redaction tests；只有报告格式实际改变时才调整预期，本计划不改变格式。
- [ ] 更新 `verify-real-controller-source.mjs`：删除旧 disclosure/fact-grid/metadata-grid 与 Actions generic-form 强制项，增加两套纯投影、单 scroll、自适应 layout、单 report、dispatcher inventory 和无额外 remote mutation 约束。
- [ ] 更新 `.trellis/spec/frontend/workbench-ui-contract.md`，替换旧 Diagnostics archetype，并记录全 controller Actions recovery/command contract、`WorkbenchActionsPresentation.swift` ownership 与 source assertions。

回退点：测试约束可观察行为和安全边界，不写只匹配局部实现字符串的 tautological assertions。

## Phase 7. Consolidated Validation

按最小相关到完整范围执行：

```bash
swift test --filter WorkbenchManagementProjectionTests --scratch-path tmp/codex/swift-build
swift test --filter AppModelEndpointChecksTests --scratch-path tmp/codex/swift-build
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
python3 ./.trellis/scripts/task.py validate 08-09-diagnostics-workspace-redesign
```

- [ ] 若新增独立 Diagnostics test suite，先运行其 filter，再运行上述相关和完整检查。
- [ ] 若新增独立 Actions test suite，先运行其 filter；确认全 controller inventory 与 dispatcher-boundary cases 均执行。
- [ ] 加载并执行 `trellis-check`，修复 spec drift、编译、测试、数据流和无障碍问题。
- [ ] 只重跑失败所影响的最小检查，最终再确认完整验证结果。
- [ ] 清理 `tmp/codex/swift-build` 和所有 disposable artifacts。
- [ ] 不运行 runtime smoke；记录需要用户使用真实 controller 验收的视觉、选择、滚动和故障状态。

## Phase 8. Finish And Commit

- [ ] 加载 `trellis-update-spec`，确认新 Diagnostics + Actions durable contract 已完整进入 frontend spec，且没有无关 spec churn。
- [ ] 检查 task-scoped diff 与当前 dirty tree，确认没有带入无关用户修改。
- [ ] 只 stage 本任务拥有的精确文件；若 overlapping untracked/dirty 内容无法安全归属，停止提交并向用户说明，不覆盖或回退它们。
- [ ] 按 Phase 3.4 创建任务 commit，然后运行 `/trellis:finish-work` 流程。

## Phase 9. Post-Audit Pre-Development Gate

- [x] 用户明确批准最新 PRD、design 和本实施计划总结；“采用完整范围”只解决范围问题，不替代最终实施批准。
- [x] 加载 `trellis-before-dev`，重新读取当前 task context、相关 Workbench/live-session specs 与 dirty-tree 状态，保留所有无关修改。
- [x] 以 `diagnostics-audit-before` 和 `diagnostics-audit-before-repeat` 为性能基线，确认报告 checksum/schema 一致，并记录 10,000-row connection median 的正常波动。
- [x] 先补写能稳定复现 evidence fallback、Auto Detect checking、first-baseline Available Now、retained controller failure dedup 和 effective Actions availability 的 focused tests；统一实现前的测试按预期暴露 7 个 management issue 和 2 个 identity issue。

回退点：本阶段除测试与 task artifacts 外不修改产品行为；若现有 fixture 无法表达某项问题，先修订设计，不通过字符串解析伪造场景。

## Phase 10. Correctness, Privacy And Accessibility Fixes

- [x] 在 `WorkbenchDiagnosticsPresentation.swift` 中让 checking 成为单一前置门：首个 baseline 前不生成 adapter/endpoint/domain/live failures，也不发布 Available Now。
- [x] 让 controller-access 在首次失败和 retained failure 中都压制同一根因的 endpoint/domain 派生问题，同时保留 retained freshness 与最后成功数据。
- [x] 修改通用 evidence helper，过滤失败时只使用本地化 unavailable fallback；endpoint typed status fallback 保持显式且安全。
- [x] 在 `WorkbenchActionsPresentation.swift` 中先计算 effective availability，再由它统一生成 recovery、target correction、groups、related destinations 与 rendered state。
- [x] 仅在 unsupported/few-command composition 显示 related workspaces；正常命令页不增加填充区域。
- [x] 为 critical/warning 增加 English/Simplified Chinese severity label；Issue Button 暴露明确的 VoiceOver label/value，装饰 symbol 不参与朗读，并保留 selected trait、键盘和 Reduce Motion 行为。

回退点：每项纯投影修复可独立回退；不得以隐藏全部技术详情规避 evidence 安全问题，也不得恢复旧 Actions grouped form。

## Phase 11. Measured Shared Performance Pass

- [x] 在 `MicaPerformanceBenchmarkTests` 增加 prepared-state 计时 helper 和 `log-steady-state-delta-projection`，setup 不计时；保留旧 end-to-end case 和报告 schema。
- [x] 实施并测量 `WorkbenchStableRowIdentityBuilder` 惰性 fallback、唯一 reported-ID 快速路径和容量预留；语义测试通过后因收益不足整体撤回。
- [x] 临时 focused identity test 证明唯一 ID 惰性路径有效；随未保留的优化一并移除，既有 duplicate/missing/collision 测试继续保留。
- [x] 连续生成 `diagnostics-audit-after` 与 `diagnostics-audit-after-repeat`；checksum/work units 全部一致，其他 case 没有连续回退超过 10%。
- [x] 10,000-row median 仅改善 6.38% 与 4.71%，未过 10% 门槛，因此撤回 identity slice；稳态日志 32 delta median 为 27.13/27.26 ms，未发现需要改写 Logs cache 的缺陷。
- [x] 未修改 Proxies scroll scheduler/hover suppression，未增加 package，未改变 live publication cadence、ring bounds 或 revision fallback。

回退点：correctness fixes 与 benchmark fidelity 不依赖 identity 优化；性能 slice 未达 stop rule 时必须可以单独撤销。

## Phase 12. Focused Contracts And Consolidated Validation

- [x] 更新 `WorkbenchManagementProjectionTests`、performance benchmark 与 source verifier assertions，覆盖最终 snapshot 和 runtime-row observation boundary。
- [x] 更新 `workbench-ui-contract.md`：first-baseline truthfulness、安全 evidence fallback、retained causal dedup、one effective Actions state、evidence-free Actions rows，以及重复基准/停止规则。
- [x] 加载并执行 `trellis-check`，修复了 Actions 通过 full diagnostic rows 观察 `controllerSession` 的 fan-out；没有派发 implement/check sub-agent。
- [x] 集中运行 focused tests、两份 benchmark after reports、source verifier、localization JSON、build、312-test 完整套件与 `git diff --check`；task validation 在 closeout 执行。
- [x] 未启动 Mica、未运行 runtime smoke、未联系 controller、未执行任何远端 mutation。SwiftUI Instruments 留作另行授权的手工验收。

建议验证顺序：

```bash
swift test --filter WorkbenchManagementProjectionTests --scratch-path tmp/codex/swift-build
swift test --filter WorkbenchOverviewPerformanceTests --scratch-path tmp/codex/swift-build
scripts/run-performance-benchmarks.sh diagnostics-audit-after-1
scripts/run-performance-benchmarks.sh diagnostics-audit-after-2
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
python3 ./.trellis/scripts/task.py validate 08-09-diagnostics-workspace-redesign
```

## Phase 13. Durable Closeout

- [x] 加载 `trellis-update-spec`，已将状态门、evidence、effective Actions state、观察边界和性能停止规则写入 durable frontend contract。
- [x] 检查精确 task diff 与 overlapping dirty files；相关 tracked/untracked 文件叠加此前重构，无法安全隔离本轮增量，按保护规则不 stage、不 commit、不归档，也不覆盖或回退用户修改。
- [ ] 按 Trellis Phase 3.4 创建任务 commit；随后执行 `/trellis:finish-work`，归档 task 并记录 journal。
- [ ] 最终向用户报告功能缺陷修复、两组 before/after 指标、保留或回退了哪些性能 slice、全部自动验证结果，以及未运行的 runtime/真实 controller 验收。

## Final Review Gate

- [ ] 用户已审核并明确批准最新 PRD、design 和 implement 总结。
- [ ] 规划阶段只修改 task artifacts 与生成离线 baseline；批准前不修改产品源码或测试。
- [ ] `task.py validate 08-09-diagnostics-workspace-redesign` 在实施前通过。
- [ ] 实施完成后向用户明确说明自动检查结果、未运行 runtime smoke，以及真实 controller 视觉验收项。

## Phase 14. Full Workbench Measured Hotspot Audit

- [x] 扩展 Release benchmark：Connections initial cache/search、Logs search、Rules index/rows/search、Sources rows/search、Proxies catalog/expanded groups；fixture 构造或 prepared cache setup 不进入目标计时区间。
- [x] 生成 `workbench-hotspots-before` 与 `workbench-hotspots-before-repeat`，记录 fixture/checksum/work units 和正常波动。
- [x] 优化 Connections 结构行格式化：每轮只解析一次 unavailable 文案，对已归一非空摘要直接组合；不改变 identity、controller order、search blob、inspector 或 revision fallback。
- [x] 用共享 `WorkbenchDataSearch` 替换 Connections、Logs、Rules、Sources 高频搜索中的逐行 localized matcher，并新增 Unicode/重音语义回归测试。
- [x] 撤回预折叠完整 blob、Swift `String.range` 和强制内联实验；它们分别出现显著回退、数量级回退或无可重复收益。
- [x] 生成 `workbench-hotspots-after` 与 `workbench-hotspots-after-repeat`；目标 Connections row/cache/search 和 Logs search 均连续改善超过 10%，可比 case checksum/work units 一致，无无关 case 连续回退超过 10%。
- [x] 完成逐页停止判断：Rules/Sources 不增加状态缓存，Proxies 不重复改写滚动调度，Overview 和固定/低基数页面不做无证据改动。

回退点：Connections 格式化与共享搜索 helper 可独立回退；benchmark/fixture coverage 保留为后续性能回归合同。

## Phase 15. Continued-Audit Quality Gate

- [x] 加载并执行 `trellis-check`，核对 spec、数据流、复用、Swift 6.2 并发/类型、测试和 benchmark fidelity。
- [x] 运行 focused projection tests、最终两轮 Release 报告核对、source verifier、localization JSON、`swift build`、完整 `swift test`、`git diff --check` 与 task validation。
- [x] 确认没有启动 Mica、接触 controller、访问 9090 或执行任何远端动作；runtime/Instruments 未运行。
- [x] 检查 overlapping dirty files；因无法安全隔离而不 stage、不 commit、不归档任务，最终结果明确说明。
