# 连接页面原生视觉重构设计

## 1. 设计结论

Connections 采用“紧凑连接概览 + 高密度原生表格 + 同窗口上下文详情”。概览负责回答当前结果集有多少连接、正在传输多少、累计传输了多少、主要由谁产生；表格继续负责扫描和排序；选中连接后才展开完整决策链与检查器。

| 决策 | 结论 |
|---|---|
| 主体控件 | 保留一个 SwiftUI 原生 `Table`，不改为卡片列表或自绘网格 |
| 首屏概览 | 使用真实连接投影生成一条紧凑 pulse strip，不复制 Overview 时间序列、拓扑或网络信息 |
| 统计范围 | 跟随活动/已关闭范围及当前搜索结果；搜索生效时同时显示“可见 / 总数”，避免统计与表格不一致 |
| 活动连接指标 | 连接数、当前上传速率、当前下载速率、累计传输量和主要来源分布 |
| 已关闭指标 | 连接数、累计上传、累计下载、累计传输量和主要来源分布；不把历史数据伪装为实时速率 |
| 主要来源 | 复用既有 `WorkbenchConnectionOwnerIdentity`：Inner、进程名、源地址、未报告；按数量降序，首次出现顺序作为稳定同值顺序 |
| 详情 | 完整决策链保留在表格上方的紧凑上下文带，完整字段保留在同窗口 inspector |
| 性能 | 聚合进入投影缓存；结构或筛选变化时重建，指标变化时仅按变化索引修正，不在 View body 扫描全集 |
| 依赖 | 不新增第三方包，不新增控制器 API，不改变会话和关闭语义 |

## 2. 数据与状态边界

现有数据流保持不变：

`MicaCore ConnectionSnapshot -> generation-owned AppModel catalog -> WorkbenchConnectionProjectionCache -> Connections views`

- `ConnectionSnapshot`、`ClosedConnectionRecord` 和控制器报告顺序仍是事实来源。
- `WorkbenchConnectionRow` 继续保存静态扫描文本和已格式化指标；表格行不读取完整 session，也不执行过滤、排序、聚合或 JSON 格式化。
- `WorkbenchConnectionProjectionCache` 继续区分 structure、metrics、closed revision，并新增可等值比较的概览投影。
- 断线、暂停、失败和 stale 继续由 `WorkbenchDataStateResolver` 与 stale notice 表达。页面不能在失去当前 generation 后把旧指标标为实时。
- 关闭操作继续验证控制器 ID、generation、能力和非空控制器连接 ID；视觉重构不能扩展可操作集合。

## 3. 概览投影

新增纯值类型 `WorkbenchConnectionPulseProjection`，至少包含：

- 当前可见连接数与当前范围总数。
- 上传、下载与合计字节数。
- 活动范围的上传、下载实时速率；已关闭范围不生成实时速率。
- 按 `WorkbenchConnectionOwnerIdentity` 聚合的前 3 个来源及“其他”数量。
- 是否处于筛选结果、是否存在控制器报告值等显示语义。

缓存更新规则：

1. scope、structure revision、closed revision 或 search query 改变时，按 `filteredSourceIndices` 重建概览和来源桶。
2. metrics revision 改变时，沿用 `ConnectionsCatalogChange.changedMetricIndices`；仅对当前筛选集合中的变化行更新上传、下载和速率合计。
3. 单纯排序变化不重建概览，因为结果集合未变。
4. 语言变化只重新格式化显示值；不改变数值、来源身份或排序。
5. 空值保持“未报告”语义，不补零、不制造样本；只有控制器明确报告的数值参与对应合计。

为便于单元测试，原始数值与来源桶保留在投影层，字节和速率文案由已有 `WorkbenchDataFormat` 统一生成。概览视图只消费预计算结果。

## 4. 页面结构

### 4.1 命令栏

- 左侧保留 Connections 图标、可见/总数和活动或已关闭语义。
- 中部保留原生 segmented scope picker；搜索继续使用窗口现有搜索入口。
- 右侧只保留当前范围合法的破坏性命令：活动范围关闭全部，已关闭范围清空历史。
- 命令栏不重复 pulse strip 中的全部指标，也不随 loading/empty 状态改变高度。

### 4.2 紧凑连接概览

- 只在有内容或筛选为空但仍有源数据时占据固定的紧凑信息带；真正无数据状态不显示空壳概览。
- 使用四个无卡片嵌套的 readout：连接、上传、下载、总流量。常规宽度单行，紧凑宽度由 `ViewThatFits` 降为两行。
- 活动范围上传/下载主值显示速率，次值显示累计量；已关闭范围只显示累计量并明确历史语义。
- 主要来源使用一条稳定、可访问的比例带和文字图例。来源名称来自真实进程或源地址，不截断后另造别名；完整值可通过 help/accessibility 读取。
- 颜色仅区分上传、下载、活动和中性来源，不使用大面积填充、渐变、装饰玻璃或持续动画。

### 4.3 表格

- 保持一个 `Table` 和一个根滚动所有者，继续使用 full / compact / stacked 列预算。
- 完整模式按目标、进程/网络、规则/链路、上传、下载、时间排列；紧凑模式组合字段但不改变数据含义。
- 行高和列宽稳定；实时指标只更新数字，不触发布局切换。
- 选择、键盘导航、排序、滚动恢复和工作区持久化沿用现有实现。

### 4.4 选中连接上下文

- 决策链改为紧凑的横向路径带，常规宽度显示：来源/进程 -> 入站 -> 规则 -> 策略/节点 -> 目标；窄宽度自然换为有限两行，不创建横向滚动。
- 可精确解析的规则和策略组保留整段可点击区域；不可解析项只读显示。
- 单项关闭与同来源组关闭靠右放置，并继续进入同窗口确认；已关闭连接不显示关闭动作。
- inspector 使用身份、路由、传输、附加信息四组；已知字段不在附加字段重复，结构化值逐项或折叠显示，禁止输出大段机器键值串。

## 5. 状态与交互

- `noController`、`loading`、`unsupported`、`empty`、`filterEmpty`、`failed` 使用统一 page fill 和剩余 viewport 居中。
- `filterEmpty` 保留命令栏，并显示清除搜索后的真实总数；不显示零值伪概览。
- stale 数据保留可读表格但以 stale notice 明确标识，pulse strip 不显示实时徽标或实时动画。
- scope、控制器、generation 或目标集合改变时，选中项与关闭确认按现有协调器重新校正。
- Reduce Motion 下禁用数值过渡和路径带动画；普通模式只允许短暂数值内容过渡，不对整表施加隐式动画。

## 6. 文件组织

`WorkbenchConnections.swift` 已同时包含投影、缓存、页面、路径带和 inspector。为降低后续维护成本，本任务按职责拆分，但不制造一组件一文件：

- `WorkbenchConnections.swift`：连接行投影、概览投影、缓存、排序与关闭 intent。
- 新增 `WorkbenchConnectionsView.swift`：页面状态、命令栏、pulse strip、原生 Table 和工作区持久化。
- 新增 `WorkbenchConnectionDetails.swift`：决策链、关闭上下文和 inspector。
- `WorkbenchDataShared.swift` / `WorkbenchVisualSystem.swift`：仅在确有跨数据浏览器复用价值时增加小型原语；Connections 特有组件不放入共享文件。
- `Localizable.xcstrings`：新增概览、历史语义、来源分布和 accessibility 文案的英文与简体中文。
- `WorkbenchDataProjectionTests.swift`：覆盖概览、缓存和布局无关的数据合同；关闭安全测试继续留在既有测试文件。

拆分是机械移动与局部重构，不改变 internal 可见性、SwiftPM target 或 AppModel API。

## 7. 性能与验证合同

- 2,000 行结构重建允许一次 O(n)；2 Hz 指标更新只处理变化指标行和必要的聚合 delta。
- owner 分布不随指标 revision 重算；搜索或结构变化时才重建。
- 表格 rows、pulse projection 和 selected detail 使用独立等值状态，避免一个小指标变化重建 inspector 或导航目录。
- 不创建 timer、轮询、Canvas、自绘表格或新的 observable 根对象。
- 使用既有 benchmark / projection tests 增加概览缓存计数断言，证明排序不重建来源桶、单行指标变化不全量重投影。

## 8. 回退边界

- 概览投影和 pulse strip 可单独回退，不影响连接表、关闭操作或控制器协议。
- 视图文件拆分可机械回退，不改变运行时数据模型。
- 若增量聚合未达到可证明的正确性，优先保留纯投影测试并退回有界 O(n) 概览重建；不得以错误统计换取微小性能收益。
- 连接页基础阶段不修改 Overview、Logs、Rules、Sources、管理页或 Settings；追加验收只修改 Proxies 的展示层。

## 9. 策略组视觉验收修正

- 组标题从带永久描边的卡片收敛为扁平分区头；展开态用细引导条和真实延迟分布表达，不增加内容玻璃。
- 节点继续使用单一 `LazyVGrid` 保留虚拟化和横向源顺序，单元最小宽度提高到常规窗口最多三列，并在较窄窗口自然退化为两列或一列。
- 节点默认不画永久边框。可用性由左侧状态轨表达，当前节点、检查项和 hover 只改变局部底色或描边；延迟测试保持独立命令但降低静止态视觉权重。
- 详情仍在所属组的节点矩阵之后，使用无嵌套卡片的三栏信息架。每栏为标题加扁平键值行，长值可选择并换行；附加控制器字段继续稳定排序、默认折叠。
- Mihomo 组目录对齐 Zashboard 的控制器配置顺序：DTO 继续保留 `/proxies` 键顺序，Dashboard 转换按 `GLOBAL.all` 中匹配的组名排列普通组，未列出项保持 DTO 相对顺序，`GLOBAL` 置尾。节点仍保持各组 `all` 顺序；Surge 与 sing-box 不套用此规则。
- 其余投影、缓存、筛选、能力门控、generation 校验和 AppModel 操作不变。
