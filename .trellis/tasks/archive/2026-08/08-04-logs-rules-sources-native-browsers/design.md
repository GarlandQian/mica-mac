# Logs、Rules 与 Sources 原生数据浏览器设计

## 1. Scope and boundaries

本任务是 `08-04-workbench-native-ui-system` 的数据浏览器阶段，只覆盖：

- `Sources/Mica/Features/Workbench/WorkbenchLogs.swift`
- `Sources/Mica/Features/Workbench/WorkbenchRules.swift`
- `Sources/Mica/Features/Workbench/WorkbenchSources.swift`
- 三页直接相关的测试、XCStrings 和源码 verifier

保留数据流：

`generation-owned AppModel catalogs -> page projection/cache -> responsive native Table -> selection -> same-window inspector`

视图不直接请求控制器，不持有新 Session，不改变 capability、认证、批量操作或重连逻辑。

## 2. Native macOS basis

- SwiftUI `Table` 继续作为三页主浏览器。它提供 macOS 原生列、选择、排序描述符和滚动行为；应用只排序展示副本，不改写源集合。
- 详情继续使用 SwiftUI Inspector，作为当前选择的同窗口尾随详情，不引入普通弹窗。
- Apple HIG 的 macOS table 指南支持有价值的列排序和可调整列宽；本任务只为真实可比较字段提供排序。

参考：

- <https://developer.apple.com/documentation/swiftui/table>
- <https://developer.apple.com/documentation/swiftui/tablecolumn>
- <https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:)>
- <https://developer.apple.com/design/human-interface-guidelines/lists-and-tables>

## 3. Shared presentation architecture

### 3.1 One table, three width modes

每页保留一个 `Table`。现有宽度解析器继续输出 full / compact / stacked 模式，列 builder 根据模式组合不同单元格，不嵌套第二个横向滚动容器，也不通过多个 Table 保留分支状态。

### 3.2 Projection ownership

- 稳定 ID、搜索文本、格式化值、可访问性文本和聚合结果由现有投影或缓存生成。
- Table cell 只读取行模型并组合轻量 SwiftUI primitive。
- 搜索无条件时返回原数组或现有缓存，避免无意义复制。
- 行更新不附加全表隐式动画；结构变化只使用 `WorkbenchMotion` 且遵守 Reduce Motion。

### 3.3 Visual hierarchy

- page fill、content fill、separator、语义色和文字由现有 Mica tokens 提供。
- 行层级采用细状态 rail、图标、主副文字和列对齐；Badge 只保留给短枚举值，不把状态或每个字段包成独立方块。
- 数字和时间使用 monospaced digit；正文根据字号自然增高，不修改全局行高或窗口几何。

## 4. Logs design

### 4.1 Table hierarchy

- full：接收时间、级别或类型、消息主体。
- compact：时间与级别合并为紧凑导语，消息主体保持主要宽度。
- stacked：首行时间与级别，次行显示可选择的完整 payload 摘要。

严重级别以窄 rail、SF Symbol 或短文本共同表达，避免厚重色块。Inspector 保留事件标识、控制器时间、类型、级别、payload、message 和结构化字段。

### 4.2 Streaming behavior

保持现有 `WorkbenchLogProjectionCache` 的增量 / delta 路径、稳定 controller ID 复用、过滤匹配缓存和 `Follow Newest` 协调器。选择历史行视为用户检查上下文，不触发强制回底；显式返回最新才恢复。

## 5. Rules design

### 5.1 Full-width columns

宽布局拆为：

1. `#`：报告 index；缺失时使用展示序号，但不改变身份或排序语义。
2. Type：短类型标签和状态 rail。
3. Payload：主要可选择文本，获得剩余宽度。
4. Target：目标策略或节点；只有精确可见策略组匹配时具备导航语义。
5. Activity：活动连接与命中信息的紧凑组合。
6. State：安静状态文字与已有 inline mutation intent。

compact / stacked 继续复用 `ruleCompactSummary`、`ruleStackedRow` 等既有入口，但调整文本层级以保留 type、payload、target、activity 和 state。

### 5.2 Selection and navigation

选中后 focus rail 按 `type -> payload -> target` 展示决策路径。Inspector 继续提供定义、统计和额外元数据。目标导航只调用现有精确策略组解析和 Workbench route intent，不从字符串猜测节点或策略组。

## 6. Sources design

### 6.1 Table hierarchy

- full：名称 / 类别、配置、数量、更新时间、能力 / 状态。
- compact：名称和类别为主，数量和更新时间压缩为次要文本，状态与动作共用尾部单元格。
- stacked：首行来源身份和状态，次行显示配置、数量和更新时间。

当前 boxed status badge 改为小状态点、图标和短文本。选中行的 focus rail 只显示该来源当前生命周期、批次进度和可执行命令，不重复整行字段或制造第二组卡片。

### 6.2 Batch update contract

视图继续调用现有 typed Update All intent。底层 `updateTargets` 保持报告顺序过滤；共享 provider task 串行执行，逐项进度可见但 catalog 只在终点刷新一次。页面改造不得创建额外 Task、取消当前 batch 或让单项操作与 batch 竞态。

## 7. State and accessibility

- Loading：保持 command bar，Table 区域居中加载。
- Empty：catalog 成功但为空。
- Filtered empty：catalog 非空但查询无结果。
- Partial / stale：保留最后真实行，移除实时语义并显示现有 notice。
- Unsupported / failed-before-first-snapshot：使用统一页面级状态，不制造空行。

每行提供组合式 accessibility label/value；可执行 target、更新和日志跟随动作提供 hint。颜色始终配合文字或 symbol。

## 8. Compatibility, risk, and rollback

- 风险：Rules 新列在窄宽度产生横向滚动。缓解：沿用宽度预算和 compact / stacked 组合，不增加第二滚动轴。
- 风险：Sources 状态简化后降低可辨识度。缓解：状态点、图标和文本三者至少保留两种信号。
- 风险：持续日志流因动画或选择更新卡顿。缓解：不对全表动画，保留增量缓存和 0.2 秒滚动合并。
- 风险：源码 verifier 对结构敏感。只更新能表达长期架构合同的断言，不为实现细节建立脆弱字符串检查。

三个页面相互独立，可按文件回退展示层修改；任何投影变更必须同时回退对应测试。控制器与 Session 层不在回退范围内，因为本任务不修改它们。
