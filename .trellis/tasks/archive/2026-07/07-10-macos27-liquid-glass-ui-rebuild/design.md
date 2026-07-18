# Mica macOS 27 Liquid Glass UI Design

## 1. Design Read

Mica 是面向高频代理控制工作的原生 macOS 专业工具。新界面采用 macOS 27 的空间材质、同心圆角和交互玻璃反馈，但不做全屏玻璃拟态，也不牺牲真实数据的完整可读性。

设计参数：

- Design variance: 6/10。允许明显重构和非对称层级，但保持 Mac 工具的稳定结构。
- Motion intensity: 5/10。动效集中在导航、选择、展开和状态反馈。
- Visual density: 7/10。数据页面紧凑、可扫描，概览和策略组保留更强的视觉层次。

## 2. Architecture Boundary

This remains one Trellis task rather than a parent with child tasks because the window shell, navigation state, localization, visual tokens, verifiers, and destination migrations share the same SwiftUI root and must move in a controlled sequence. Phase 2 may still delegate disjoint destination slices to sub-agents after the new shell contract is stable.

保留：

- `AppModel`、Mihomo/Surge 适配器、控制器能力矩阵、命令执行、Keychain/凭据边界。
- `/proxies` 与成员原始顺序、真实连接/规则/来源/日志字段、运行时状态。
- `AppLanguage`、`AppAppearance`、`AppFontScale` 与本地化基础设施。

替换：

- 当前 `ContentView`、`WorkbenchRootView`、`WorkbenchSidebarView` 的视觉/导航职责。
- `WorkbenchDestination` 的 10 项平铺信息架构。
- `MicaSurface`、`MicaPanel`、旧卡片和自定义按钮体系。
- 当前手写表格、操作顶栏和 Command 菜单分组。

不创建旧类型包装器。迁移完成后直接删除旧 UI 概念并更新调用点、校验器和文档。

## 3. Window Composition

新主窗口建议拆分为：

```text
MicaApp
└── MicaWorkbenchWindow
    ├── NavigationSplitView
    │   ├── MicaSidebar
    │   └── WorkbenchAreaHost
    ├── Native unified toolbar
    ├── Optional same-window inspector
    └── Bottom operation/status bar
```

### Sidebar

- 使用原生 `List(selection:)`、Section、键盘焦点与系统选择态。
- 顶部是紧凑控制器切换区：当前控制器名称为主，完整 endpoint 可换行和选择；添加/编辑进入主窗口编辑模式。
- 五个主区固定顺序：
  1. Overview / 概览
  2. Proxies / 代理
  3. Activity / 活动
  4. Rules & Sources / 规则与来源
  5. System / 系统
- 不再显示“Command 菜单”“Controller Command”等抽象分区标题。

### Toolbar

- 系统统一工具栏自动获得 macOS 27 Liquid Glass。
- 高频控制器动作：测试、刷新、Live 开关。按功能组成系统 `ControlGroup`。
- 当前区支持搜索时使用原生 `.searchable(..., placement: .toolbar)`。
- 页面专属动作由 area content 提供，不把所有动作堆在全局工具栏。
- 对不应加入共享玻璃背景的身份/状态项使用 `sharedBackgroundVisibility(.hidden)`。
- 删除顶部 `safeAreaInset` 操作条；操作结果进入底部状态栏和相关内容区域。

### Status Bar

- 使用底部紧凑状态区显示正在执行、成功、部分成功和失败状态。
- 不抢占页面标题，不持续保留普通成功消息。
- 消息、目标、下一步完整可选择；错误状态可跳转诊断。

## 4. Navigation Model

引入新的展示层导航状态：

```swift
enum WorkbenchArea: String, CaseIterable, Identifiable {
    case overview
    case proxies
    case activity
    case resources
    case system
}

enum ActivitySection { case connections, logs }
enum ResourceSection { case rules, sources }
enum SystemSection { case configuration, actions, diagnostics, settings, tailscale }
```

- `WorkbenchArea` 持久化最后选择。
- 子区由每个 area 自己持久化。
- Tailscale 只有在控制器能力明确支持时出现在 System 分段中。
- 菜单快捷键 `⌘1` 至 `⌘5` 对应五个主区；子区使用 `⌥⌘1...` 或菜单项，不覆盖标准快捷键。

## 5. Liquid Glass System

### Native First

- 先删除自定义导航/工具栏背景，让系统组件自动采用当前 Liquid Glass。
- 自定义玻璃只用于有交互和层级价值的元素，不对普通文本、表格行或日志逐项加玻璃。
- 使用系统 `.buttonStyle(.glass)` / `.glassProminent`，避免重写按压、高亮和禁用表现。

### Custom Glass Primitive

只保留一个小型语义组件，例如：

```swift
struct MicaGlassSelectionSurface<Content: View>: View
```

职责：

- 根据 selected、interactive、semantic tint 和 Reduce Transparency 选择表现。
- macOS 27 使用 `glassEffect`、`GlassEffectContainer`、`ConcentricRectangle`。
- Reduce Transparency 时使用系统 `Color(nsColor: .controlBackgroundColor)`、清晰边界和系统选择色。
- 不提供任意 shadow、gradient、radius 参数，防止重新形成无约束样式系统。

### Color

- 窗口和内容背景使用系统语义颜色/材质。
- Rose Pine 仅保留为应用 accent 与语义状态 tint：紫色用于主选择，青色用于实时/信息，黄色用于等待，红色用于失败/危险。
- 不再用 Rose Pine 固定背景铺满整个窗口。
- 图表可使用 upload/download 两个相关但可区分的语义色；其他页面不扩张成多彩卡片集合。

### Shape

- 玻璃选择块使用 `ConcentricRectangle` 与容器形状匹配。
- 按钮优先系统形状；状态标签只在需要命中区域时使用 capsule。
- 内容表格、Section 和 inspector 不额外包圆角卡片。

## 6. Area Designs

### Overview

结构从上至下：

1. 控制器身份、完整 endpoint、类型、版本、模式、健康与最近更新时间。
2. 实时流量主视图：真实 upload/download 时间序列存在时显示 Swift Charts；无样本时显示明确的未开始/不可用状态。
3. 累计流量与真实对象数量，以大数字和分隔布局呈现，不使用等宽卡片墙。
4. 运行时和端点状态使用紧凑表格。

新增 `TrafficTimeline` 展示模型：

- 只接收真实 live traffic 事件。
- 固定容量环形缓冲区，按收到时间记录，不插值、不生成占位样本。
- 切换控制器或停止/重置会话时清空，避免跨控制器混合。
- Chart 与文字当前值共用同一真实样本源。

### Proxies

宽窗口：

- 左侧/上部是固定顺序的自适应 Liquid Glass 策略组选择块。
- 右侧是所选组的同窗口详情与成员列表。
- 选择只改变 `selectedPolicyGroupID`，不移动、排序或重建原数组。

窄窗口：

- 玻璃块保持固定顺序。
- 所选组详情在选择区域后原位展开，不使用 sheet/popover。

策略组块显示：完整组名、类型、当前选择、成员数、hidden 状态、测试/切换状态。成员区使用高可读列表，显示完整节点名、类型、延迟和选择态；节点行不是独立玻璃卡片。

`GlassEffectContainer` 仅包裹可见策略组选择块。可以使用 `glassEffectID` 做选中块到详情标题的材质连续动画，但动画不得改变项目顺序或布局 identity。

### Activity

- 顶部原生分段：Connections / Logs。
- Connections 使用 SwiftUI `Table`，支持列宽调整、排序仅限用户明确请求的本地视图模式；默认保持控制器顺序。
- 选中连接在同窗口 inspector 显示完整 ID、host、process、addresses、rule payload、chains 和流量。
- Logs 使用高密度列表/表格，支持 level、暂停、follow bottom 和 clear；完整消息可选择和换行。
- 高风险关闭连接继续使用同窗口确认状态或平台标准 destructive confirmation。

### Rules & Sources

- 顶部原生分段：Rules / Sources。
- Rules 使用 payload-first `Table`，详情展示完整 payload/type/proxy。
- Sources 分代理来源与规则来源，显示名称、vehicle、behavior、count、updatedAt 和 capability。
- 更新操作使用同窗口状态和能力门控。

### System

- 顶部原生分段：Configuration / Actions / Diagnostics / Settings；Tailscale 条件出现。
- Configuration 和 Settings 使用 `Form`、`Section`、`LabeledContent`、原生 Picker/Toggle/TextField。
- Actions 以任务组分区，不做操作卡片墙；危险动作有清晰层级和最小必要确认。
- Diagnostics 使用 Table/DisclosureGroup 展示 endpoint、能力和覆盖范围，复制报告在工具栏或菜单可达。
- 同一 `MicaSettingsForm` 同时用于 System 区与标准 Settings scene，避免两套状态逻辑。

## 7. Controller Editing

- 添加/编辑控制器仍在主窗口完成。
- 使用 System/Form 风格编辑器替代当前 `MicaSurface` 卡片组合。
- Save/Cancel/Test 放在原生工具栏；错误和审计结果显示在相关字段或底部状态区。
- endpoint 和控制器名称完整显示，Secret/X-Key 仍按凭据字段处理。

## 8. State And Accessibility

统一状态组件只描述语义，不规定卡片外观：

- loading: 与最终行结构一致的占位/ProgressView，不伪造数据。
- unavailable: 明确控制器不支持或端点未提供。
- empty: 支持但返回空集合。
- filtered empty: 原数据存在但当前筛选无结果。
- partial/error: 显示真实错误摘要与可执行下一步。
- live/paused: 工具栏和内容同时有一致状态。

辅助功能：

- 使用语义字体样式，必要的 monospaced 只用于 endpoint、ID、payload、计数和协议值。
- 长业务字段换行或进入可调整 inspector，不使用中间截断。
- 图标按钮有本地化 label、help 和键盘入口。
- 玻璃背景在 Reduce Transparency 下有清晰实色替代；Reduce Motion 关闭 morphing，仅保留状态切换。

## 9. Migration And Rollback

按纵向切片迁移，任何阶段保持应用可构建：

1. 新导航状态、窗口 shell、toolbar/status bar。
2. 新视觉 tokens 与唯一玻璃选择组件。
3. Overview 与真实时间序列。
4. Proxies 策略组浏览器。
5. Activity 与 Resources 表格/inspector。
6. System、Settings、Controller Editor。
7. 删除旧 UI 文件/键，重写 verifier、runtime smoke、spec/docs。

不保留运行时旧 UI 开关。若某阶段失败，通过 Git 提交边界回退整个纵向切片，而不是添加兼容适配器。

## 10. Verification Design

- 单元测试：策略组/节点顺序、真实流量 timeline 容量和控制器切换清空、availability 显示决策。
- 源码校验：新五区架构、旧 UI 删除、原生玻璃/API 使用、modal 禁令、全量字段和无 archived-task 依赖。
- Runtime smoke：新菜单、五区/子区、本地化、外观、字体和辅助功能样本。
- UI smoke：中文/深色/超大字体、英文/浅色/标准字体、系统外观/舒适字体；至少验证宽窗和最小窗。
- 人工视觉检查：正常透明度、Reduce Transparency、Reduce Motion、键盘、VoiceOver、长控制器/策略/节点/ID 文本。
- 无控制器 smoke 只验证真实空/不可用状态；不注入 mock 控制器数据。

## 11. Durable Contract Updates

实现完成后同步更新：

- `AGENTS.md`：当前任务描述和 Liquid Glass 长期规则。
- `.trellis/spec/frontend/workbench-ui-contract.md`：五区导航、玻璃层级、全量可见和验证契约。
- `docs/UI_GUIDELINES.md`、`docs/ARCHITECTURE.md`、`docs/DEVELOPMENT.md`。
- `scripts/verify-real-controller-source.mjs`：移除归档任务路径和任务状态耦合。
