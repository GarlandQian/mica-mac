# Workbench 剩余源码职责拆分

## Goal

在不改变 Workbench UI、控制器数据顺序、能力门控、会话 generation、刷新节奏、持久化格式或用户操作语义的前提下，将剩余同时承担多类职责的大型源码按稳定所有权拆分。根页面只负责组合与 intent，纯投影和缓存、交互调度、详情组件、持久化及窗口协调分别进入明确文件；已经职责单一的文件保持不动，不以行数为目标制造碎片。

## Confirmed Facts

- 当前 Workbench 已有 30 个明确列入源码合同的文件；Proxies 刚完成 root / panels / interaction / presentation 四层拆分，不属于本任务的再次重构对象。
- `WorkbenchChrome.swift` 同时拥有 destination、窗口根、侧栏、工具栏、状态栏和 operation outcome 呈现；这些部分的更新原因不同。
- `WorkbenchVisualSystem.swift` 同时拥有设计 token 和通用 SwiftUI scaffold；`WorkbenchDataShared.swift` 同时拥有滚动/viewport 协调、通用视图以及投影/selection helper。
- Connections、Logs、Rules、Sources 当前都将根 View、纯投影/缓存和详情 View 放在同一编译单元；Connections 还将 pulse 缓存与 pulse strip 放在不同大文件中。
- Actions 同时承载通用操作页和 Tailscale 工作区；Controllers 与 Diagnostics 同时承载纯投影和 SwiftUI 页面/组件。
- `WorkbenchOverviewPersonalization.swift` 同时拥有布局模型、持久化 store、冲突处理和窗口协调；这些职责具有独立的变化与测试边界。
- Dashboard、Overview telemetry/topology、Proxy panels/presentation、Configuration、Settings 与 `WorkbenchWorkspaceStore` 虽然部分文件较长，但现有职责内聚；继续机械拆分只会扩大访问级别并产生小文件。
- Workbench 使用精确文件清单，源码 verifier 还按具体文件切片检查 destination、sidebar、表格、投影和详情所有权。新增文件必须同步合同、聚合和 ownership 断言。
- 当前 worktree 含大量用户未提交修改。本任务必须以它们为基线追加，不能回退、覆盖或提交混合历史。

## Requirements

### R1. Shell and shared system ownership

- `WorkbenchChrome.swift` 只保留 destination、根 Workbench 组合与 app lifecycle。
- 新增 `WorkbenchWindow.swift`、`WorkbenchSidebar.swift`、`WorkbenchStatusBar.swift`，分别拥有窗口内容/编辑器呈现、侧栏、会话控制与底部状态/operation outcome 呈现。
- 新增 `WorkbenchDesignSystem.swift` 拥有 `MicaStyle`、token、spacing、bounds、typography 和通用 motion/modifier；`WorkbenchVisualSystem.swift` 只保留共享 SwiftUI primitives、scaffold 和状态视图。
- 新增 `WorkbenchDataInteraction.swift` 拥有宽度、响应式布局、scroll/viewport/performance 协调；`WorkbenchDataShared.swift` 保留通用 browser/inspector View；新增 `WorkbenchDataPresentation.swift` 拥有纯 data state、resolver、projection、formatting、stable identity 与 selection helper。

### R2. Data page ownership

- Connections 新增 `WorkbenchConnectionCache.swift` 拥有 reported metric、pulse projection/cache 和 metric sort cadence；新增 `WorkbenchConnectionPulseView.swift` 拥有 pulse strip、metric 和 owner distribution View。现有 Connections 文件分别保留页面投影/intent、根表格和详情。
- Logs 新增 `WorkbenchLogPresentation.swift` 拥有 row/severity、projection/cache 和 follow cadence；`WorkbenchLogs.swift` 只保留根表格与 inspector View。
- Rules 新增 `WorkbenchRulePresentation.swift` 拥有 row/index/cache/projection、navigation 与 decision path model；新增 `WorkbenchRuleDetails.swift` 拥有 decision path rail 和 inspector；`WorkbenchRules.swift` 只保留根表格。
- Sources 新增 `WorkbenchSourcePresentation.swift` 拥有 row/projection/focus/cache；新增 `WorkbenchSourceDetails.swift` 拥有 focus rail、update-all progress 和 inspector；`WorkbenchSources.swift` 只保留根表格。
- 保持所有行顺序、过滤、selection、inspector、滚动、pulse/follow cadence、cache invalidation 和控制器报告可见性不变。

### R3. Management page ownership

- `WorkbenchActions.swift` 保留通用 action confirmation/projection 和根页面；新增 `WorkbenchTailscale.swift` 拥有 sing-box Tailscale section、endpoint 与 peer View。
- 新增 `WorkbenchControllerPresentation.swift` 拥有 controller delete/list/connection-test 的纯投影；`WorkbenchControllers.swift` 保留状态 View、根页面和 test report View。
- 新增 `WorkbenchDiagnosticsPresentation.swift` 拥有 diagnostics field/projection/support/visibility 逻辑；新增 `WorkbenchDiagnosticsComponents.swift` 拥有共享/detail SwiftUI 组件；`WorkbenchDiagnostics.swift` 只保留根页面组合。
- Configuration、Settings 和 Management shared definitions 保持现有所有权。

### R4. Overview personalization ownership

- `WorkbenchOverviewPersonalization.swift` 保留 layout/configuration/normalizer/preset/row packing/effective model。
- 新增 `WorkbenchOverviewLayoutStore.swift` 拥有 persistence client/envelope、typed mutation 与 store。
- 新增 `WorkbenchOverviewWindowCoordinator.swift` 拥有 conflict model、window coordinator 与 draft state。
- 持久化 key、编码格式、migration、conflict resolution、窗口身份和草稿语义必须保持不变。

### R5. Mechanical and access constraints

- 按完整顶层声明块迁移，保留类型名、成员名、实现顺序和输入输出；只调整必需的 imports 与访问级别。
- presentation/cache 文件尽可能只依赖 `Foundation`/`MicaCore`；SwiftUI-only appearance extension 留在 View 所有者文件。
- 只有真实跨文件入口可从 `private`/`fileprivate` 放宽为 module-internal；leaf View、cache key 和实现 helper 保持私有。
- 不复制 helper 或业务逻辑，不创建兼容别名，不增加 package，也不移动状态到新的 observable model。

### R6. Executable contracts and documentation

- 更新 Workbench 精确文件清单、各文件 ownership 说明和 `docs/ARCHITECTURE.md` 中受影响的架构摘要。
- verifier 为 shell、shared data、Connections、Logs、Rules、Sources、management 与 Overview personalization 建立真实的多文件聚合，同时保留具体文件的正反 ownership 断言。
- 不削弱 controller order、optional data、capability、generation、cache、selection、destination、sidebar、table、detail 或 persistence 合同。
- 仅在现有测试因文件职责/预期行为必须同步时修改测试；本次纯拆分不以新增覆盖率为目标。

## Acceptance Criteria

- [x] AC1：shell、visual system 和 shared data 按 R1 的目标文件边界落位，根文件不再拥有交互调度、token 或纯 presentation/cache 职责。
- [x] AC2：Connections、Logs、Rules、Sources 按 R2 拆分，页面根、纯投影/cache 与详情/pulse View 的 ownership 清晰，现有数据与交互语义不变。
- [x] AC3：Actions/Tailscale、Controllers 和 Diagnostics 按 R3 拆分，纯投影不再依赖 SwiftUI，页面入口与 capability/generation 门控不变。
- [x] AC4：Overview personalization 的模型、store 和 window coordination 按 R4 分离，持久化与冲突处理测试保持通过。
- [x] AC5：Dashboard、Overview telemetry/topology、Proxies、Configuration、Settings 和 WorkspaceStore 等已内聚文件没有被无意义继续拆碎。
- [x] AC6：新增文件全部进入精确源码合同；verifier 聚合与 ownership 断言同步，原有业务断言没有被删除或放宽。
- [x] AC7：定向 Workbench 测试、source verifier、Swift build、完整 Swift tests、localization JSON、`git diff --check` 和 Trellis validate 全部通过。

## Out Of Scope

- 不重新设计 UI、布局、Liquid Glass、动画、可访问性、文案或交互。
- 不修改 AppModel/MicaCore API、controller DTO、capability、authentication、session runtime、网络或刷新行为。
- 不改变本地化资源、持久化 schema/key、控制器数据顺序、optional data 或错误呈现语义。
- 不继续拆分已经内聚的 Overview chart/topology、Proxies、Configuration、Settings、WorkspaceStore 或小型页面。
- 不重构 verifier 的全局框架，不引入 package，不启动 Mica，不访问真实控制器，不运行 runtime smoke。
- 不创建、提交或推送 Git commit，不归档父任务；本任务只在当前 dirty worktree 上完成源码拆分与验证。

## Key Decisions

- “剩余全部”解释为所有经审计仍混合不同所有权/更新频率的 Workbench 源码，而不是按行数拆每个大文件。
- 采用 feature-local 的 root / presentation / interaction-or-details 边界；文件名直接表达所有权，不新增目录层级或 Swift package。
- 迁移是行为中性的声明重定位。任何需要算法、状态流或 UI 调整的问题都应单独记录，不混入本任务。

## Risks And Deferred Items

- 多文件迁移会暴露隐式 `private`/`fileprivate` 依赖；实现只修复最小访问边界，不能通过复制逻辑绕过。
- verifier 目前按单文件切片，若只拼接字符串可能掩盖 ownership 漂移；设计要求同时保留 per-file 正反断言。
- shared projection/cache 被多个页面消费，因此即使无行为修改也必须运行完整 Swift 测试。
- 当前 dirty worktree 无独立提交边界；最终只报告本任务差异与验证结果，不执行 Git 历史操作。
