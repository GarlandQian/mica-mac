# 控制器管理原生工作区重构设计

## 1. Scope and ownership

本任务修改现有类型，不建立平行管理架构。数据流保持：

`Controller adapter -> MicaCore domain model -> generation-owned AppModel state -> management projection -> SwiftUI view`

SwiftUI 只读取现有 AppModel presentation/catalog 并发送 intent。Profile persistence、secret persistence、session selection、config mutation、runtime operation 和 diagnostics export 继续由 AppModel 拥有。

该范围不再拆子任务。机械文件迁移、共享表单原语和四个页面文件存在直接编译耦合，单一任务可以设置一个清晰的“机械拆分 build”回退点，并在此后统一完成视觉重构。

## 2. File decomposition

目标 Workbench 文件职责：

| 文件 | 所有权 |
|---|---|
| `WorkbenchManagement.swift` | 跨管理页复用的 width mode、header、form canvas、form row/value、状态/布局小原语 |
| `WorkbenchControllers.swift` | controller delete/test/list projections、Controllers master-detail、controller report/detail subviews |
| `WorkbenchConfiguration.swift` | Configuration projection/view、config field controls |
| `WorkbenchActions.swift` | runtime confirmation/projection、Actions view、现有 backend-specific action subviews |
| `WorkbenchDiagnostics.swift` | diagnostics field/support/visibility projections、outline/disclosure/status helpers、Diagnostics view |
| `WorkbenchSettings.swift` | 已完成的独立 Settings scene 内容，不迁回 management |

迁移规则：

1. 以完整类型和其私有 extension 为单位移动，先不改布局或文案。
2. 页面只使用的 helper 与页面同文件，继续为 `private`。
3. 共享 helper 留在 `WorkbenchManagement.swift`，保持当前 module-internal 可见性；不引入 `public` API。
4. 如果一个现有 `private` helper 确实被两个新文件消费，先判断能否消除共享；无法消除时才提取为最小 module-internal primitive。
5. 更新 Workbench 精确文件合同和 `verify-real-controller-source.mjs`：新增 management page file 数组，将原先只读取 `WorkbenchManagement.swift` 的断言改为读取相关聚合源码，同时保持直接本地化 key 扫描覆盖所有新文件。
6. 机械移动完成后运行一次 `swift build`。失败只修复文件边界，不混入 UI 改动。

SwiftPM target 自动发现源文件，`Package.swift` 无需增加文件条目。

## 3. Shared presentation system

管理页面继续使用：

- `WorkbenchPageScaffold` 与 `WorkbenchCommandBar`
- `WorkbenchManagementFormCanvas`、共享 form row/value 原语
- `MicaStyle`、`MicaSpacing`、`MicaBounds`、`WorkbenchMotion`
- `micaFont` 与现有四档 `AppFontScale`
- 系统 `List`、`Table`、`HSplitView`、`VSplitView`、`Form` 和 SwiftUI disclosure

内容区使用不透明语义 fill 与 separator。系统窗口/toolbar/sidebar 承担 Liquid Glass；管理内容不添加 `.thinMaterial`、`.ultraThinMaterial` 或自定义 glass。内容圆角上限为 8pt。

宽度模式只由根容器的可用宽度计算一次。行在 regular 布局中采用稳定标签列，字段值在标签列后左对齐，只有操作命令靠尾部对齐；compact 布局允许内容自然堆叠。字号只改变文本，不参与断点决策。

## 4. Controllers and editor

### 4.1 Controllers state

`WorkbenchControllerListProjection` 继续负责：

- 在 profile 原始数组上按查询过滤，不排序。
- 按 stored selection、active controller、first visible profile 的优先级协调详情选择。
- 选择身份使用 profile ID，不使用数组 offset。

Workspace 结构：

- 左/上 master：原生 controller list，整行选择，展示状态、名称和安全目标摘要。
- 右/下 detail：身份、连接状态、控制器类型、最近测试与命令区。
- Use、Test、Edit、Delete、Move Previous、Move Next 只存在于详情命令上下文。选择 master 行没有网络副作用。
- Use 调用现有 `selectRouter`；Test 使用现有 per-profile test intent；移动调用 `moveRouter`；编辑打开现有 `RouterEditorPresentation`；删除调用现有 profile transaction。

`WorkbenchControllerDeleteConfirmation` 继续封装 controller ID 和 generation。任何 selection/session generation 变化都清除 pending confirmation。删除 active controller 后的 replacement 规则保持 AppModel 现状，不在 View 复制。

### 4.2 RouterEditor state

`RouterEditorView` 保持本地 `draft`、`initialDraft`、test state、save state 和 discard state。输入只更新本地 draft；保存时调用一次 `upsertRouter(from:)`。该事务继续：

1. 解析旧 secret；
2. 暂存或更新 `FileSecretStore`；
3. 保存完整 profile 数组；
4. 失败时恢复旧 secret；
5. 成功后一次性发布 profiles，并仅在既有条件下更新活动 session。

视图调整仅重组现有 sections：删除重复可见 label，让字段值在稳定标签列后左对齐；窄宽度自然换行。连接测试不成为保存前置条件，避免改变既有产品语义。

## 5. Configuration

Configuration 继续从当前 `dashboard.config`、controller type 与 capability projection 形成可见字段。字段存在且 mutation action 受支持时才创建 row。

每次写入仍调用 `updateControllerConfig(_:)`：

- 保存 previous config；
- 在主 actor 乐观应用 typed mutation；
- 记录 controller ID 与 generation；
- 通过现有 client 更新并读取权威 config；
- 只在相同 session 回收结果；
- 请求失败恢复 previous config，刷新失败保留 partial 结果。

View 不直接创建 client，不解析动态 JSON，也不创建 YAML 编辑器。进行中的字段由现有 `updatingConfigFieldID` 局部标识，避免整页 loading。

## 6. Actions

`WorkbenchActionsProjection` 以 capability-backed runtime rows 形成稳定、有序、仅可执行的列表。Backend-specific subviews 仍由其真实模型和 intent 驱动。

普通命令可直接执行；破坏性或生命周期命令先创建 `WorkbenchRuntimeConfirmation`，其中包含 controller ID、generation、operation ID。确认前再次核验：

- 仍是同一 selected controller；
- generation 未改变；
- operation 仍在当前 capability projection 中；
- 没有同 operation 正在执行。

确认 UI 原地替换对应行的命令区，不弹 Alert。Session 改变或 row 消失时取消确认。执行结果复用 AppModel `operationState` 与 command history，不在 UI 伪造成功。

## 7. Diagnostics

Diagnostics 分为两层 presentation：

1. `WorkbenchDiagnosticsVisibleProjection`：在进入 body 前按当前支持能力移除 unavailable rows、空组和机器字段。
2. SwiftUI outline：消费稳定、可本地化的 row/field 值，只负责展示和 disclosure state。

页面结构：

- 结论带：诊断状态、连接状态、兼容状态、最近结果和建议操作。
- 基础事实：当前控制器和经过 redaction 的安全目标摘要。
- 详细检查：一个纵向 outline；一级 section 和二级 row 都使用整行 `Button` + `contentShape(Rectangle())`。
- 展开内容：用户可读的现状、影响和建议；机器细节不在 active UI 形成 assignment wall。

一级、二级 disclosure 共用同一 animation helper，Reduce Motion 时不做 transition。外层保留一个主滚动容器；展开内容使用普通 `VStack`，不在 lazy row 内再嵌套 `LazyVStack`、`List` 或 `ScrollView`。字段格式化在 projection 构建时完成，row body 不扫描全部诊断集合。

Copy Report 继续走 AppModel diagnostics export；UI redaction 与 export redaction 分层，active UI 可简明，报告可保留安全技术细节。两者都不得包含 credentials、authorization、subscription URL、secret store 内容或 raw response/stream body。

## 8. Localization and accessibility

- 新增可见 key 同时写入英文与 `zh-Hans`；不拼接占位格式串。
- controller 行、配置字段、action 行、diagnostics status/disclosure 使用组合 accessibility label/value/hint。
- 状态同时使用 symbol 与文字，不只用颜色。
- 全行交互通过真实 `Button` 或 selection 实现，键盘 Return/Space 和 VoiceOver 行为可预测。
- `micaFont` 覆盖新增文本，数字状态使用 monospaced digit 语义。

## 9. Compatibility and dependencies

- 保持 Swift 6.2、macOS 27、SwiftPM 和现有依赖集合。
- 不引入 AppKit-hosted content、第三方 UI/diagnostics 包或新的持久化系统。
- 不改变 controller adapter、API endpoint、DTO/domain mapping、runtime cadence 或 reconnect policy。

## 10. Risk and rollback

- **文件拆分风险**：机械迁移独立完成并 build；该边界是首个回退点。
- **访问级别风险**：完整 ownership island 一起移动，优先消除共享，禁止为方便把 helper 公开。
- **会话误操作风险**：所有确认和异步回收复用 controller ID + generation，UI 不缓存可跨会话执行的闭包。
- **顺序回归风险**：过滤 projection 保持输入次序，移动只调用持久化 transaction。
- **诊断性能风险**：投影预计算、稳定 ID、单滚动所有者、无嵌套 lazy 和无全树 animation。
- **共享视觉回归风险**：只扩展确有多个消费者的现有 management primitive，不修改无关 Overview/Data Browser 页面。

若 UI 阶段出现问题，只回退对应页面文件；不撤销已通过 build 的机械拆分，也不使用破坏性 Git 命令。
