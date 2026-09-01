# Mica Workbench 跨页面 UX 验收与优化

## Goal

在不更换既有 Mica Ops 视觉体系、不重写已验收页面的前提下，完成 Workbench 最后一轮跨页面 UX 验收与修复。用户在全部核心页面之间切换、筛选、选择、检查详情和执行操作时，应保持清晰上下文、准确状态、稳定布局和流畅反馈；浅色/深色、四档字号、中英文与不同窗口宽度下应使用同一套可预测交互。

## Background And Confirmed Facts

- 本任务是父任务 `08-04-workbench-native-ui-system` 的 Phase 5 子任务。Phase 1-4 已建立共享视觉系统、10 个目的地、原生 Settings、单一 workspace inspector、数据浏览器和管理页面骨架；本任务只修复可复现的跨页面缺陷和验收缺口。
- 当前 10 个 Workbench 目的地及分组由 `WorkbenchDestination` 唯一定义（`Sources/Mica/Features/Workbench/WorkbenchChrome.swift:6`）；RouterEditor、Settings、菜单/工具栏和全局 Shell 一并纳入 14 模块验收矩阵。
- `WorkbenchWorkspaceView` 是 10 个目的地的唯一分发点（`Sources/Mica/Features/Workbench/WorkbenchWorkspaceView.swift:38`），详情统一由根级 inspector 承担，页面不得新增自己的 `.inspector`。
- 数据浏览器已经共享同一 scaffold 与原生 Table 约束（`Sources/Mica/Features/Workbench/WorkbenchDataShared.swift:44`）；本轮不得把它们重新做成卡片、并行数据源或页面级滚动系统。
- Mica 是高密度 macOS 专业工具。内容层保持不透明、平面和可扫描；Liquid Glass 只由系统导航/控制层提供，不在内容区增加自定义 glass、辉光、装饰渐变或悬浮卡片。
- 当前 `overview-flow-ribbons` 任务已实现长链横向视口，但仍待浅色/深色用户目验；本任务在其验收后处理跨页面联动和可访问性，不重新设计拓扑视觉。
- 自动验证不得启动 Mica、读取用户控制器配置、连接真实控制器或执行远程操作。运行时逐页视觉验收由用户完成，除非用户另行明确授权 visual-only smoke。

## Requirements

### R1. Cross-surface continuity

- 切换目的地、控制器或 session generation 时，页面选择、workspace 持久状态和 inspector 状态必须按各自所有权更新，不显示上一页面已经失效的详情。
- Inspector 的标题栏关闭按钮必须同时关闭 inspector 列并清除其当前详情；工具栏开关只控制列可见性，不伪造或迁移业务选择。
- 每个 inspectable selection 必须能解析到唯一 owning destination。切页时隐藏不属于新目的地的详情，但保留各目的地合法的 workspace selection，使返回页面时能够通过现有恢复路径重新定位。
- 跨页面跳转（规则到策略组、连接到规则/策略组、拓扑到连接/策略组）继续校验 controller ID、generation 和目标身份；目标缺失、被过滤或过期时给出准确恢复动作，不静默落到错误条目。
- 主要命令可由菜单、工具栏或键盘到达；原生 Table/List 选择、搜索焦点、Escape 退出确认/详情和侧边栏方向键行为保持一致。

### R2. Responsive hierarchy and space balance

- 14 模块在窄/中/宽窗口和 `standard / comfortable / large / extraLarge` 四档字号下无文本重叠、按钮标题丢失、无意义横向滚动、断点抖动或大面积失衡空白。
- Command bar 的标题、状态、筛选和命令在中英文及 Extra Large 下稳定换行；工具栏命令不与页面 command bar 重复同一身份或动作。
- 数据浏览器保持一个 Table 和一个主内容滚动所有者。管理/操作页面保持 leading-anchored 有界画布；少量操作不能被拉成跨越整个大窗口的稀疏两行，也不能用虚构数据填满页面。
- Overview 继续拥有唯一纵向滚动。仅已批准的长链拓扑允许有界横向视口；短链不得产生横向滚动，横向溢出必须可发现且键盘选择后能够定位到有效锚点。
- Settings 和表单保持原生 grouped Form；字号变化只影响文字，不缩放窗口、工具栏、状态栏、表格行和断点阈值。

### R3. Truthful state and command feedback

- 每个目的地区分 no-controller、loading、unsupported、empty/unloaded、filter-empty、failed-before-first-value、stale-retained 等状态；同一状态在 command bar、内容区、status bar 和 inspector 中不得互相矛盾。
- stale 数据继续完整显示并带明确说明；controller switch 或 generation end 才清除 session-bound 数据和选择。暂停只冻结展示，不伪装成断线或空数据。
- capability、pause、busy 和 generation 门控必须在按钮可用性与 AppModel 执行边界一致；完成、部分成功和失败结果使用既有 status bar/inline feedback，不新增普通模态流程。
- 筛选导致当前选择不可见时，列表、辅助 rail 和 inspector 必须按同一 reconciliation 结果更新，不能留下只在一处存在的选择。

### R4. Confirmed UX defects and focused fixes

- 修复 inspector 关闭语义不完整：当前 `selectInspector(.none)` 只清空 selection（`WorkbenchWorkspaceStore.swift:549`），而 UI 把该按钮标为关闭 inspector（`WorkbenchDataShared.swift:304`）。
- 修复目的地切换期间的失效 inspector：当前根生命周期只更新 live demand（`WorkbenchChrome.swift:260`），未处理 inspector selection 与 destination 的所有权关系。
- 为长链拓扑补齐视口定位：当前横向 `ScrollView` 与键盘 `movePathSelection` 之间没有 scroll target 联动（`WorkbenchOverviewTopologyView.swift:425`、`:577`）。选择节点、边或路径后至少一个语义锚点必须进入视口；Reduce Motion 下即时定位。
- Actions 在命令数不超过 2 时已经提供 related destinations（`WorkbenchActionsPresentation.swift:207`），但 command canvas 仍固定放宽至 1080pt（`WorkbenchActions.swift:343`）。应根据真实命令密度使用紧凑有界宽度，保留所有真实命令和跳转，不增加占位说明或假数据。
- 审计过程中发现的其他问题只有在具备源码、测试、可重复布局条件或用户截图证据时才进入实现；不以主观“换皮”扩大范围。

### R5. Accessibility and localization

- 所有图标命令具有英文和简体中文 label/help；状态不能只靠颜色表达。关闭、定位、跳转和重试的 VoiceOver 语义与实际行为一致。
- Keyboard-only 用户可完成：切换目的地、搜索/筛选、选择列表行、打开/关闭 inspector、遍历拓扑路径、执行非破坏性命令和取消确认。
- 尊重 Reduce Motion、Reduce Transparency 和 Increased Contrast。自定义动画只用于有限状态变化；Inspector/拓扑定位在 Reduce Motion 下无动画但不丢行为。
- 所有新文案进入 `Localizable.xcstrings`，英文与 `zh-Hans` 参数签名一致，不泄漏 key、`%@` 或混合语言。
- Mica 的 pointer-first macOS 控件合同优先：独立图标控制使用 28pt frame、整行控件填满可点击行；不套用移动端统一 44pt 行高。

### R6. Performance and invalidation discipline

- 不新增页面 timer、重复 debounce、广域 `AppModel.controllerSession` 观察或 body 内全集过滤/排序/格式化。
- Inspector destination gating 和 Actions 宽度决策必须是 O(1) 的纯状态/投影；拓扑定位复用现有 layout/index，不重新构建图结构或扫描 SwiftUI 子树。
- Connections/Logs 各 2,000 行、大规则集、大 Sources 集、多策略组展开和完整 Diagnostics disclosure 下，滚动、切页、筛选和窗口 resize 不出现新的明显卡顿。
- 涉及既有 hot path 时运行两组可比 Release benchmark。保留优化必须满足目标 case 两次 median 至少改善 10%，且无无关 case 连续回退超过 10%；纯 UX 修复至少不得让相关 case 连续回退超过 10%。

### R7. Scope and dependency discipline

- 先完成或明确接管 `08-23-overview-flow-ribbons` 的用户视觉验收，再修改其拓扑交互；不得同时维护两个冲突的 Overview 视觉方案。
- 使用现有 `MicaTheme`、Workbench primitives、workspace store 和 AppModel 操作，不新增第三方包或兼容层。
- 每一处产品代码修改必须映射到本 PRD 的缺陷/验收项，并配套测试或 verifier 断言；纯格式化和无证据重构不进入本任务。

## Acceptance Criteria

- [ ] AC1：14 模块完成浅色/深色、四档字号、窄/中/宽窗口审计；无重叠、关键标题截断、断点抖动、不必要横向滚动或显著失衡空白。
- [ ] AC2：点击任一 inspector 标题栏关闭按钮后，详情 selection 清空且 inspector 列收起；对应页面行选择按既定语义同步，不留下空白 inspector。
- [ ] AC3：目的地切换不显示上一页详情；返回 Connections、Rules、Logs、Sources、Controllers 或 Proxies 时，合法的 per-destination workspace selection 可由现有恢复路径重新定位。
- [ ] AC4：长链拓扑通过键盘、点击或跨页面定位选择节点/边/路径时，有效语义锚点自动进入横向视口；短链保持无横向滚动；Reduce Motion 行为等价。
- [ ] AC5：Actions 在 0、1、2 和多命令场景下均保持紧凑、leading-aligned、可扫描布局；只显示真实 capability 命令和既有 related destinations。
- [ ] AC6：no-controller、loading、unsupported、empty、filter-empty、failed-first、stale、paused 和 partial 场景在页面、command bar、inspector 与 status bar 中无矛盾，命令门控一致。
- [ ] AC7：英文/简体中文和四档字号下，菜单、help、tooltips、按钮、Inspector 与格式参数完整；VoiceOver/键盘/Reduce Motion 合同通过源码与定向测试。
- [ ] AC8：controller switch、generation end、stale reconnect、pause/resume 和 destination visibility 的现有生命周期测试通过，旧确认/旧选择/旧结果不能作用于新会话。
- [ ] AC9：2,000 Connections、2,000 Logs、大规则/来源集、多展开策略组和 Diagnostics disclosure 的相关测试/benchmark 通过；没有可重复的 >10% 性能回退。
- [ ] AC10：`swift build`、完整 `swift test`、source verifier、XCStrings JSON、对比度审计、`git diff --check` 和当前/父任务 Trellis validate 全部通过。
- [ ] AC11：用户使用真实控制器完成浅色/深色逐页视觉验收；自动验证不连接控制器、不执行远程操作、不运行未经授权的 runtime smoke。

## Out Of Scope

- 不替换 Mica Ops 颜色、字体、间距、图标或页面 archetype，不再次进行全局视觉重构。
- 不新增目的地、Command Palette、Dashboard 假指标、启动项、自动故障转移、控制器操作或配置字段。
- 不修改 controller HTTP/WebSocket/gRPC、DTO、能力声明、重连节奏或系统网络/OpenWrt 行为。
- 不新增自定义内容 glass、辉光、装饰渐变、嵌套卡片、普通 modal 或第三方 UI/状态框架。
- 不将 runtime visual smoke 视为自动完成条件；真实控制器视觉验收仍由用户触发和执行。

## Key Decisions

- 采用“跨页面连续性 + 可复现缺陷”验收，不做新一轮换皮。
- Inspector 选择继续是 window-level、session-bound；目的地切换隐藏不属于新页面的详情，页面自己的 selection 仍由现有 per-destination workspace 保存。
- Actions 少命令场景通过自适应内容宽度和既有相关工作区补足信息密度，不制造更多操作。
- Overview 只补交互定位和跨页面一致性，沿用 `overview-flow-ribbons` 已批准的固定核心构图与长链方案。
- 没有阻塞规划的产品问题；实施仍需用户在本规划总结之后单独明确批准。

## Risks And Deferred Items

- SwiftUI `onAppear`/`onDisappear` 与 destination change 顺序可能导致 selection 被误清；设计要求把隐藏 inspector 与清除 page selection 分成不同操作，并用 store 单测锁定。
- 拓扑自动定位若直接触发全树 animation 可能造成滚动卡顿；只允许 scroll-position 状态变化，并受 Reduce Motion 门控。
- 当前 Workbench UI 合同仍含“拓扑不使用横向视口”的旧句，与已批准的长链实现存在 spec drift；在 Overview 用户验收后通过 `trellis-update-spec` 收敛为短链无横滚、长链条件横滚。
- 真实控制器、不同数据规模和实际窗口截图无法由自动测试代替，最终视觉目验保留给用户。
