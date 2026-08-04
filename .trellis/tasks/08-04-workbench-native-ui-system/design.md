# Mica Workbench 全局原生 UI 重构设计

## 1. Delivery Architecture

本任务采用父任务统筹、页面簇子任务交付。父任务拥有统一需求、共享视觉合同、依赖顺序和最终集成验收；子任务拥有可独立实现、验证和回退的页面切片。

现有 `08-03-connections-native-visual-rebuild` 已关联为子任务，继续完成 Connections 与其中已经批准的 Proxies 展示修正。其余子任务在父任务通过最终规划审查后按顺序创建，避免提前生成大量空任务。

建议任务树：

1. `connections-native-visual-rebuild`：Connections + 已纳入的 Proxies 修正，现有任务。
2. `workbench-shell-settings-foundation`：全局壳、侧边栏、工具栏、Settings、共享视觉原语。
3. `overview-native-monitoring-workspace`：Overview 图表、拓扑、网络信息和个性化布局。
4. `logs-rules-sources-native-browsers`：Logs、Rules、Sources 三个数据浏览器。
5. `controller-management-native-workspace`：Controllers、RouterEditor、Configuration、Actions、Diagnostics，并拆分过大的管理文件。
6. `workbench-cross-surface-acceptance`：跨页面颜色、字号、状态、性能、本地化、可访问性和生命周期验收。

子任务按以上顺序推进。后一个子任务可以复用前一阶段已经稳定的共享原语，但不能静默改变已验收页面的业务语义。

## 2. Repository Map

| 模块 | 真实类型 | 主要源码 |
|---|---|---|
| Overview | `WorkbenchOverviewView` | `Sources/Mica/Features/Workbench/WorkbenchDashboard.swift` 及现有 `WorkbenchOverview*.swift` |
| Proxies | `WorkbenchPolicyGroupsView` | `WorkbenchProxies.swift`, `WorkbenchProxyGroupPanels.swift` |
| Connections | `WorkbenchConnectionsView` | `WorkbenchConnections.swift`, `WorkbenchConnectionsView.swift`, `WorkbenchConnectionDetails.swift` |
| Logs | `WorkbenchLogsView` | `WorkbenchLogs.swift`, `Sources/Mica/App/SessionBuffers.swift` |
| Rules | `WorkbenchRulesView` | `WorkbenchRules.swift` |
| Sources | `WorkbenchSourcesView` | `WorkbenchSources.swift` |
| Controllers | `WorkbenchControllersView` | `WorkbenchManagement.swift` |
| Add/Edit Controller | `RouterEditorView` | `Sources/Mica/Features/Routers/Views/RouterEditorView.swift` 及现有 editor section 文件 |
| Configuration | `WorkbenchConfigurationView` | `WorkbenchManagement.swift` |
| Actions | `WorkbenchActionsView` | `WorkbenchManagement.swift` |
| Diagnostics | `WorkbenchDiagnosticsView` | `WorkbenchManagement.swift` |
| Settings | `MicaSettingsSceneView` | `WorkbenchManagement.swift`, `Sources/Mica/App/MicaApp.swift` |
| Menu/Toolbar | `MicaApp`, Workbench chrome | `MicaApp.swift`, `WorkbenchChrome.swift` |
| Global Shell | `ContentView`, `WorkbenchRootView`, `WorkbenchSidebarView` | `WorkbenchChrome.swift` |

实施必须修改这些既有类型。拆文件时类型名称、入口和所有权保持不变，不新增 `MicaDashboardView`、`MicaConnectionsView` 等平行架构。

## 3. Layer Boundaries

### 3.1 Controller and runtime

控制器 DTO、领域模型、capability、认证、会话 generation、刷新协调和实时发布节奏保持现状。UI 只调用现有 AppModel 操作，不直接构造请求、不解析未知端点、不建立连接。

数据流保持：

`Controller adapters -> MicaCore models -> generation-owned AppModel catalogs -> Workbench projections/caches -> SwiftUI views`

视图读取 `controllerSessionPresentation` 和细粒度 catalog/revision，不直接观察重型 session 对象。异步操作沿用既有 AppModel generation 与 controller ID 校验。

### 3.2 Presentation projection

- 数据浏览器的过滤、排序、聚合、格式化和稳定 ID 在 projection/cache 中完成。
- View body 只组合预计算值、决定当前宽度模式并发出 intent。
- 控制器报告集合永不因本地筛选或排序被改写。
- 缺失值保持未报告语义，不补零、不伪造时间、延迟或能力。

### 3.3 AppKit boundary

继续只在既有生命周期、窗口外观、系统通知、剪贴板、颜色桥接和系统服务边界使用 AppKit。Workbench 内容、列表、表格、表单、图表、Disclosure 和 Inspector 使用 SwiftUI。设置页无需引入 AppKit 重做。

## 4. Visual System

### 4.1 Tokens

使用 `WorkbenchVisualSystem.swift` 中已经存在的语义系统：

- `MicaStyle` / `MicaDesignTokens`
- `MicaSpacing`, `MicaBounds`
- `micaFont`, `MicaTextStyle`
- `WorkbenchMotion`
- `WorkbenchSymbol`
- `WorkbenchPageScaffold`, `WorkbenchCommandBar`
- `WorkbenchSection`, `WorkbenchContentBand`
- `WorkbenchStateView`, `WorkbenchStatusBadge`, `WorkbenchStaleNotice`
- 数据浏览器专用 `WorkbenchData*` 原语

只有两个以上页面出现相同、非业务特定的组合时才提升共享组件。不得为生成稿中不存在的 `SectionCard`、`NodeBadge`、`TableContainer`、`ActionButton` 或 `CodeContainer` 造兼容层。

### 4.2 Palette and material

当前可访问 Midnight Instrument 自适应 palette 是唯一事实来源：page/content/elevated/tertiary、accent、cyan、mint、amber、red、violet。页面不得硬编码另一套 Rose Pine hex；若未来要整体换色，应作为独立 token 迁移任务完成。

原生窗口、侧边栏和 toolbar 可以使用系统提供的材质。内容区使用不透明语义 fill、细 separator 和最多 8pt 圆角；不使用 `.thinMaterial`、`.ultraThinMaterial`、自定义 `.glassEffect`、装饰渐变、阴影堆叠或卡片套卡片。

### 4.3 Typography and geometry

- 所有界面文字使用 `micaFont` 语义角色和 `AppFontScale` 的 0.92 / 1.0 / 1.16 / 1.32 倍率。
- 宽度断点只看容器宽度；字号变化允许文字换行和内容增高，但不切换页面架构。
- 表格、侧边栏、toolbar、状态栏和窗口最小尺寸不随字号成比例放大。
- 点击区域由完整 row/button label 的 `contentShape(Rectangle())` 提供，不通过固定 44pt 全局高度实现。

## 5. Page Archetypes

### 5.1 Monitoring workspace

Overview 使用“指标信息带 + 交互式时间序列 + 完整拓扑 + 网络信息”的扁平模块结构。Swift Charts 已是 Apple 框架且当前项目已经使用，不新增第三方图表包。Chart hover、pin、pause、step 和 return-live 继续消费既有有界 runtime 数据。拓扑保持完整链路、无横向滚动，并根据最密列增长高度。

### 5.2 Source-ordered policy workspace

Proxies 使用单一纵向滚动、多个可同时展开的 disclosure 和一至三列自适应节点网格。组目录和成员目录严格保持控制器顺序；节点主点击区执行现有 inspection + capability-gated switch，延迟测试是独立次要命令。详情插入所属组内并只为选中节点构造完整字段。

### 5.3 High-frequency data browsers

Connections、Logs、Rules、Sources 使用 `WorkbenchDataBrowserScaffold` 和原生 Table/Lazy 容器：

- Connections：真实 pulse summary + Table + 决策链 + inspector。
- Logs：固定容量 buffer + 流式过滤 + Follow Newest 协调。
- Rules：Table + 预索引连接命中计数 + 精确策略目标跳转。
- Sources：Table + 单项操作 + 串行 Update All 进度。

每页只有一个主滚动所有者，状态视图使用统一 page fill 和剩余 viewport 居中。

### 5.4 Management workspace

Controllers 使用 master-detail；窄宽度改为垂直 split，宽度足够时水平 split。RouterEditor 继续覆盖主内容区，使用分组 Form 和固定命令栏，不创建普通 Sheet。Configuration、Actions 使用 capability-driven Form/List。Diagnostics 使用“未装框的结论带 + 单一层级 outline + 自适应事实网格”，技术 payload 只进入安全报告。

### 5.5 Settings, menu, and shell

Settings 保留原生 Scene 和一个有界 grouped Form，只显示四类现有偏好。菜单使用 `MicaStrings` 的 menu language；toolbar 只保留当前页面命令与全局 session 控制，不重复 controller selector。Shell 保留 10 个目的地和现有 `NavigationSplitView` 生命周期。

## 6. State Semantics

- `idle/noController`：没有选择控制器，提供 Controllers 导航入口。
- `connecting/first load`：只显示 loading，不复用上一控制器数据。
- `live/partial`：展示真实可用 catalog；partial 明确指出缺失能力。
- `staleReconnecting`：保留最后成功 catalog，去除实时语义并显示 stale notice。
- `paused`：停止 presentation 推进但不伪装断线。
- `failedBeforeFirstSnapshot`：显示失败状态和既有重试/编辑路径。
- `empty`：已成功加载但 catalog 真实为空。
- `filterEmpty`：原始 catalog 非空，当前搜索无结果。
- `unsupported`：当前控制器明确不支持该页面或操作。

切换 controller、结束 generation 或删除 profile 时清理对应局部 workspace selection、确认和实时缓存。短暂重连不得清空合法 stale catalog。

## 7. File Decomposition

`WorkbenchManagement.swift` 目前约 4,876 行。管理阶段先执行机械拆分，再分别重构：

- `WorkbenchSettings.swift`
- `WorkbenchControllers.swift`
- `WorkbenchConfiguration.swift`
- `WorkbenchActions.swift`
- `WorkbenchDiagnostics.swift`
- 仅将真正跨管理页复用的 projection/form primitive 留在 `WorkbenchManagement.swift` 或一个明确的 shared 文件。

拆分不得改变访问级别、类型名称、入口、AppModel API 或测试语义。`WorkbenchProxies.swift` 和 `WorkbenchDashboard.swift` 只在职责边界明确、能降低局部重绘或维护复杂度时继续拆分；不追求一组件一文件。

## 8. Performance Strategy

- 沿用 runtime 250ms/500ms/1s/200ms 发布节奏，页面不加 timer。
- 用 revision 和 changed-index 更新 projection；静态字段与动态指标分离。
- 稳定 ID 不使用数组 offset 代替 controller identity。
- 搜索在 projection 层预计算 normalized text；查询变化使用轻量 debounce，但不阻塞流摄取。
- 只有可见 destination 建立昂贵投影；切出页面释放订阅或暂停可见计算。
- 不对持续数据流应用整棵 View 的隐式 animation。
- Instruments 指标是用户运行时验收工具；自动测试验证算法边界、重建计数、容量、顺序和 generation 安全，不写不可移植的绝对 CPU/FPS 断言。

## 9. Localization and Accessibility

可见字符串使用 `MicaStrings.localizedKey/localized`，动态格式继续由 `XCStringsResolver` 处理。菜单语言通过 `AppLanguage.menuBarLanguage`。每个子任务补齐英文和简体中文，并扫描 `%@`、占位 key 和语言混杂。

表格行、节点、状态、图表和 destructive action 提供组合式 accessibility label/value/hint。颜色同时配合 symbol、文字或线型。Reduce Motion、Increase Contrast 和键盘 focus 由原生控件优先承载。

## 10. Risk and Rollback

- **共享原语扩散风险**：共享系统单独成阶段；每次修改前列出消费者，避免一次 style 改动使所有页面回归。
- **大文件拆分风险**：机械移动与 UI 改造分开提交/检查；编译失败可单独回退移动。
- **实时性能风险**：先补 projection/cache 测试，再接 UI；错误增量统计宁可退回有界 O(n) 重建，也不显示错误数据。
- **状态语义风险**：所有页面复用 `WorkbenchDataStateResolver` 或等价既有 state projection，不在 View 自行推断连接状态。
- **视觉主观风险**：每个子任务结束由用户使用真实控制器验收截图；父任务不依赖 runtime smoke。
- **依赖风险**：默认不新增 package；任何新增依赖都必须作为显式设计变更重新经过父任务审查。
