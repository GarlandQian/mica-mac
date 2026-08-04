# Technical Design: Localization Placeholders And Management Form Alignment

## Decision Summary

在字符串目录层恢复严格的“键签名等于翻译签名”契约，并把静态 UI 标签与
参数化整句拆开。管理工作台以 `WorkbenchFormRow` 为统一字段布局边界，让
设置、控制器、配置、操作、诊断和内嵌详情共享明确的标签列、控件列和紧凑
布局。

不在渲染层清理 `%@`，不依赖宽松插值回退修补错误目录，也不新增依赖。

## Root Cause

### Placeholder Leakage

`MicaStrings.localizedKey` 对动态静态键做直接目录查找，不带参数。如果目录值
本身是 `当前控制器：%@`，结果就会原样包含 `%@`。

`MicaStrings.localized` 会把插值表达式分解为参数化语义键，例如：

```text
diagnostics.active_controller %@
```

现有目录却只定义 `diagnostics.active_controller`。因此参数化调用不能通过
正常键查找命中，只能进入宽松回退或返回内部键。根因是目录键、翻译模板和
调用方式三者契约不一致。

### Form Value-Column Drift

设置页虽然给每个 `Picker` 设置了 `.leading`，但父级默认
`LabeledContent` 仍控制值列的位置。宽表单会把这个值列放到内容中部，
子控件的 alignment 无法改变列的起点。

配置页复用了同一默认值列，并对部分 Picker 和只读文本显式使用
`.trailing`。其他页面主要使用 `WorkbenchFormRow`，说明仓库已经有正确
方向，但尚未把它设为所有管理字段的唯一边界。

## Catalog Migration

### Static And Parameterized Pairs

同时承担字段标签和报告整句的诊断概念拆为两个目录条目：

- 静态键保持现有名称，例如 `diagnostics.active_controller`，翻译值只保留
  `Active Controller` / `当前控制器`。
- 参数化键使用 Swift 插值实际生成的签名，例如
  `diagnostics.active_controller %@`，翻译值保留完整参数化句子。

这样现有 `localizedKey("diagnostics.active_controller")` 静态调用保持明确，
而 `localized("diagnostics.active_controller \(value)")` 会直接命中参数化键。

整数计数使用语义键实际生成的 `%lld`，不能仅按目录旧值中的 `%d` 机械迁移。
实施时以 `String.LocalizationValue` 分解结果和现有正确条目为准。

### Dashboard Entries

- `dashboard.switch_node` 当前是无参数按钮/辅助功能名称，改为简洁静态文案。
- 其他 `dashboard.*` 异常项先完成静态与动态引用审计。
- 有参数化消费者时建立带签名键；仅有静态消费者时改为静态文案；确认完全
  无引用且无运行时动态入口后才删除死条目。

### Structural Validation

在 `scripts/verify-real-controller-source.mjs` 增加格式签名提取：

1. 解析隐式和显式位置格式符，包括 `%@`、`%d`、`%lld`、`%1$@`。
2. 忽略 `%%`。
3. 规范化位置和长度修饰符后比较键、英文值、简体中文值。
4. 参数化值要求键声明参数；三方签名必须兼容。

验证针对整个 catalog 执行，因此以后新增键也受约束。

## Runtime Resolver Boundary

- 静态文本继续调用 `MicaStrings.localizedKey`。
- 参数化文本继续调用 `MicaStrings.localized`。
- 正确 catalog 键必须走 `resolvedTemplate` 的精确命中路径。
- `looseInterpolatedResolution` 仅保留现有兼容用途，不能成为新目录条目的
  正常解析路径。
- `XCStringsResolverTests` 增加静态标签、字符串插值、整数插值和反向重定位
  样例，锁定两条解析路径。

## Management Field Layout

### Canonical Field Row

保留并完善 `WorkbenchFormRow`，将其作为管理页面字段的唯一布局原语：

- 常规布局为左对齐 `HStack`。
- label 使用集中定义的稳定宽度。
- content 紧接标签列，内部 Busy 指示器、Picker、Toggle、TextField 或值文本
  均从左侧开始。
- content 后方吸收剩余空间，不允许默认值列把内容推向中部或右侧。
- 紧凑布局为左对齐 `VStack`。
- 行继续保留最小命中高度、动态字体、多行文本、文本选择和辅助功能语义。

`WorkbenchFormRow` 已被控制器编辑、控制器详情、诊断和部分配置详情使用，
因此扩展现有原语比新增第二套设置专用 style 更一致。

### Width Resolution

- `WorkbenchManagementCanvas` 和 `WorkbenchManagementFormCanvas` 继续在根部
  计算一次离散宽度模式。
- `WorkbenchPreferenceForm` 为 Workbench 和原生 Settings 两个 host 在根部
  解析可用宽度并注入相同模式。
- 不在大量配置行中重复运行 `ViewThatFits`。
- Picker 内已有的低数量 segmented/menu 退化可保留。

### Surface Migration

- 设置：`nativePreferenceRow` 改为 canonical field row。
- 配置：`configurationRow` 改为 canonical field row；模式、日志级别和
  只读文本从 trailing 改为 leading。
- 控制器编辑、控制器详情、操作和诊断：审计所有字段调用，保留或迁移到
  canonical row，删除局部对齐例外。
- Tailscale 等 disclosure：字段名和值使用明确的 leading 组合；不使用默认
  `LabeledContent` 值列。
- 工具栏、头部计数和状态摘要不迁移，因为它们不是字段行。

同一个 `WorkbenchPreferenceForm` 仍同时用于 Workbench 和 Settings scene；
Picker 类型、绑定和帮助文案不变。

## Alternatives Rejected

### Strip Tokens At Render Time

会隐藏目录和调用契约错误，并可能删除合法百分号。拒绝。

### Keep Default LabeledContent And Add More Frames

子控件 frame 不能改变父级值列起点，无法稳定满足左对齐。拒绝。

### Add A Settings-Only LabeledContentStyle

只能修复截图页面，配置和内嵌详情仍会漂移，并产生第二套字段规范。拒绝。

### Replace Forms With Custom Cards

扩大视觉范围并丢失原生 Form 行为，不符合本次字段修复。拒绝。

### Add A Third-Party Localization Or Form Library

系统与现有本地实现已足够，依赖没有材料收益。拒绝。

## Compatibility And Rollback

- 不修改偏好键、`AppPreferencesStore`、控制器模型或导出结构。
- 目录迁移保持英文与简体中文覆盖完整。
- Catalog 更改可按静态/参数化条目组回滚；字段行迁移可按设置、配置和内嵌
  详情分组回滚，不需要兼容包装层。
- 不保留错误的旧参数化静态值作为兼容副本。

## Verification Strategy

1. 运行全目录格式签名审计并确认异常数从 31 降为 0。
2. 运行聚焦 resolver 测试，证明静态和参数化路径都正确。
3. 运行源码契约验证，锁定目录规则和管理字段统一左对齐原语。
4. 运行完整 Swift 构建与测试。
5. 使用英文/简体中文、标准/超大字体检查设置、控制器、配置、操作、诊断和
   内嵌详情；这不是旧 runtime smoke，也不连接真实控制器。

## Approved Follow-Up: Proxy Node Field Inspector

### Data Boundary

`ProxySnapshot` 已保留 Mihomo 节点对象的全部顶层 `metadata`，因此不修改
控制器 API 或 DTO。`ProxyNodeViewState` 继续保存原始元数据，并额外保留
控制器明确上报的 `UDP`、`UOT`、`XUDP`、`TFO`、`MPTCP`、`SMUX` 布尔状态，
包括 `false`。

### Presentation Boundary

`ProxyMemberDetailProjection` 仅为当前选中节点生成按键排序的原始字段行。
字符串直接显示；数字、布尔值和 `null` 使用稳定标量文本；数组和对象使用
键排序的紧凑 JSON。该投影不存入整个节点目录，避免大型目录为不可见节点
重复编码原始字段。原始 `now` / `all` 仍在检查器完整显示，但不重复写入
目录搜索 JSON，因为当前选择和成员名称已有独立索引。

检查器复用 `WorkbenchDataInspectorSection` 和字段行节奏，分为概况、传输
能力、测试与延迟、控制器字段。控制器字段逐项可选择；普通节点切换和延迟
测试按钮保持不变。没有弹窗、嵌套滚动或新依赖。

## Approved Follow-Up: Management Settings Visual Hierarchy

管理页保留 SwiftUI 内容边界，不引入 AppKit 表单控件。共享画布从居中改为
左侧锚定：普通管理内容最大 920 点、Form 最大 860 点、偏好内容最大 760 点。
`WorkbenchFormRow` 的标签列从 208 点收紧到 176 点，并允许在标签下显示现有
帮助文案。

Workbench Settings、Actions、控制器详情和 Diagnostics 复用
`WorkbenchContentBand`：不透明 content fill、上下 Divider、无圆角、无阴影，
因此形成清晰分区但不成为浮动卡片。Configuration 和原生 Settings 继续使用
系统 grouped `Form`，移除两侧 Spacer 居中框架并注入明确的 scroll content
margins。数据、绑定、操作、确认和状态机均不变。

## Approved Follow-Up: Preference Control Chrome

四个偏好选项复用泛型 `WorkbenchPreferenceMenu`，以原生 `Menu` 作为交互
边界。收起时只显示当前选项的 SF Symbol、文字和一个下箭头；展开后使用
原生菜单项，并以 checkmark 标识当前值。菜单采用 borderless 样式且隐藏系统
重复指示器，不绘制自定义背景、边框或玻璃。

外观与字体大小不再使用 segmented Picker，避免连续按钮块。菜单直接写入
现有 Binding，因此语言、外观、字体和 GLOBAL 可见性仍即时生效；同时补充
accessibility label/value 和原有 help。

## Approved Follow-Up: Rules Scan Hierarchy

规则页保留既有投影缓存、单 Table、原始顺序、搜索与用户排序，只重组单元格。
full 模式以 payload 为主、类型与索引为副信息，后续显示路由、活跃连接、
命中数及状态；状态单元格同时容纳可用的启停命令。compact 模式把路由、
两个活动指标、状态和命令合并为一个摘要；stacked 模式只构造一列完整复合行。

规则状态使用 6 点语义色圆点和次要文字，不再使用带背景的 badge。规则主列
使用中性分支图标，避免与状态重复编码。完整定义、统计、元数据和 mutation
错误继续由同窗口 inspector 承载。
