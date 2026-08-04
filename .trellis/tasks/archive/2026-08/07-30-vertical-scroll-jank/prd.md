# 垂直滚动卡顿诊断与修复

## Goal

消除 Mica 全部工作台页面在静态和实时数据场景下的纵向滚动卡顿。滚动输入必须优先于非关键投影、绘制、排序和持久化，同时保持数据完整、控制器顺序、操作反馈、逐字文本选择以及完整连接拓扑。

本任务不沿用上一轮性能优化的完成结论。完成必须由新的静态滚动基线、自动化回归和主机侧 SwiftUI 性能证据共同证明。

## Approved Decision

用户于 2026-07-30 采用方案 B：使用原生 SwiftUI 统一重构滚动与展示边界。

- 每个页面只有一个纵向滚动所有者。
- 每个数据页面只构造一个原生 `Table`。
- 静态布局/绘制问题与实时发布放大问题在同一任务内修复。
- 保留逐字文本选择、完整业务数据、控制器原始顺序和完整拓扑。
- 不引入 AppKit 表格桥接或第三方滚动框架。

## Confirmed Evidence

- 用户确认断开控制器且数据静止时，首次和反复纵向滚动都卡顿，因此根因不只在实时刷新。
- `WorkbenchDataShared.swift:38` 的响应式容器会构造 full、compact、stacked 三套表格描述树。
- `WorkbenchDataShared.swift:163` 的表格单元格组合了逐字选择、垂直 `fixedSize` 和不稳定行高，持续触发布局和命中区域计算。
- `WorkbenchDashboard.swift:112` 的 Overview 外层纵向滚动与 `WorkbenchDashboard.swift:1155` 的拓扑二维滚动共享纵轴。
- `WorkbenchDashboard.swift:1258` 的拓扑 `Canvas` 同步遍历全部边、节点和标签；`WorkbenchDashboard.swift:1336` 与 `WorkbenchDashboard.swift:1368` 还会建立全尺寸命中层和完整辅助功能树。
- `WorkbenchDashboard.swift:505`、`:648` 和 `:710` 的图表标记与共享悬停状态扩大了交互失效范围。
- `WorkbenchManagement.swift:22` 已知道根宽度，但 `WorkbenchManagement.swift:169` 和 `:3562` 等重复行仍各自运行 `ViewThatFits` 候选测量。
- `AppModel.swift:82` 将连接目录作为单一可观察值；`AppModelLiveSessionRuntime.swift:383` 整体赋值后，`WorkbenchConnections.swift:699` 再重建投影，形成重复失效。
- `WorkbenchConnections.swift:491` 的缓存仍复制/循环整表；`:543` 在实时指标变化时重复排序。
- `DashboardSessionModels.swift:307` 已携带日志 delta，但 `WorkbenchLogs.swift:310` 与 `:355` 又重建完整 ring 和行投影。
- `WorkbenchLogs.swift:948` 的首次滚动阶段变化会修改 Follow Newest；`WorkbenchWorkspaceStore.swift:351` 的编码/写入路径仍可能在主线程执行。
- `WorkbenchWorkspaceStore.swift:437` 的 `scrollAnchorID` 只有写入路径，没有实际驱动滚动位置。
- `WorkbenchProxies.swift:478` 的滚动调度器由根视图状态持有，`:689` 与 `:1349` 的阶段变化可能使较大视图子树失效。

完整审计见 `research/vertical-scroll-source-audit.md`。

## Requirements

### R1. Measurement First

- 使用现有隐私安全性能观测补充 DEBUG-only 的滚动阶段、视图/投影重建、拓扑绘制和工作区持久化计数。
- 先建立断开控制器的静态基线，再验证离线大数据夹具与实时发布压力。
- 性能观测不得记录控制器地址、ID、名称、请求、规则、日志或其他业务数据。

### R2. One Vertical Owner

- Overview、策略组、数据页和管理页各自只能有一个纵向滚动所有者。
- 嵌套滚动仅允许使用与外层正交的轴。
- 完整拓扑保留在 Overview，但不得与页面外层争夺纵向输入。

### R3. Stable Native Data Tables

- 连接、日志、规则和来源每页只构造一个原生 `Table`。
- 页面根部解析一次离散宽度模式，普通状态变化不得同时构造三套表格候选。
- 表格行使用稳定单行几何；完整换行值继续在同窗口检查器中显示。
- 表格、列表和详情保留现有逐字拖选与复制能力。

### R4. Narrow Invalidation

- 页面只观察自身显示所需的稳定行 ID、静态字段、窄动态状态、选择和操作能力。
- 滚动阶段、悬停、选择和命令状态不得使整个工作台或无关页面失效。
- 当前不可见页面不得继续执行昂贵投影、图表准备或拓扑工作。

### R5. Incremental Live Data

- 连接结构与指标更新必须在展示层保持分离，指标变化按稳定 ID 更新。
- 实时指标排序在滚动期间冻结，只保留最新待提交顺序，并在滚动结束或固定时限到达时提交一次。
- 日志 append/drop delta 必须端到端进入展示层，不能每次重建完整 ring。
- 非关键实时更新只保留最新状态，不积压历史帧；错误、断开和用户命令结果绕过普通延后。

### R6. Overview Rendering

- 图表静态序列与悬停/固定读数具有独立失效边界。
- 拓扑保留每条活动连接和控制器报告的每个链路节点。
- 拓扑布局、静态绘制、高亮、命中和辅助功能表示分层缓存，并按可见区域准备绘制工作。
- 可见区域裁剪只能减少渲染工作，不能删除拓扑记录或链路。

### R7. Management Layout

- 管理页面在根部计算一次宽度模式，重复行直接使用该模式。
- 低频、低数量的原生控件可保留 `ViewThatFits`；长列表和重复表单行不得反复候选测量。

### R8. Scroll And Workspace State

- Follow Newest 只在用户开始主动滚动时改变一次。
- 选择与视口锚点分别存储；真实滚动位置必须消费锚点。
- 工作区编码基于不可变快照移出主线程，并合并到滚动空闲、页面切换、窗口关闭或固定最长期限。
- 单个滚动阶段事件不得同步编码或写入工作区。

### R9. Correctness And Cancellation

- 控制器 ID 与 generation 保护所有延后提交。
- 切换、删除、断开或 destination 变化时，旧任务和旧数据不得回写。
- 断开后不得把旧快照继续显示为实时数据。
- 策略组、节点、规则、来源、连接链路和拓扑内容及顺序保持不变。

### R10. Technology Boundary

- 保持原生 SwiftUI、Swift 6.2 和 macOS 27。
- 不访问真实控制器、本机 9090、核心进程或系统网络设置。
- 不进行无关视觉重构，不通过删减数据或交互掩盖性能问题。
- 本任务不引入 AppKit 表格桥接、第三方滚动框架或仅用于装饰的依赖。

### R11. Concentrated Verification

- 测试随实现补充，但在全部阶段完成后统一运行完整构建、测试、源码契约和性能验证。
- 不运行旧 runtime smoke。
- 最终必须保存可重复的优化前后证据；编译通过或源码存在某项优化不能单独证明完成。

## Out Of Scope

- 工作台视觉语言、导航信息架构或业务功能重设计。
- 新控制器能力、新 API 或真实控制器联调。
- 删除逐字文本选择、减少数据字段、限制拓扑链路或改变控制器顺序。
- AppKit/第三方表格替换、第三方滚动框架和无测量依据的依赖引入。

## Acceptance Criteria

- [ ] AC1: 断开控制器的 Overview、策略组、四个数据页和管理页在首次及反复纵向滚动时无明显输入滞后或周期性停顿。
- [x] AC2: 每个 destination 只有一个纵向滚动所有者，拓扑不再与 Overview 外层争夺纵向输入。
- [x] AC3: 连接、日志、规则和来源每页运行时只存在一个原生 `Table`，宽度变化保持选择、排序和滚动身份稳定。
- [x] AC4: 表格行保持稳定单行几何，表格、列表和详情的逐字选择与复制仍可用。
- [x] AC5: 滚动阶段变化不会触发无关页面重算、全量投影、同步编码或磁盘写入。
- [x] AC6: 管理页只在根部计算一次宽度模式，重复行不再各自执行响应式候选测量。
- [x] AC7: 拓扑保持所有活动连接及完整链路，静态底图、高亮、命中和辅助功能具有独立失效边界。
- [x] AC8: 图表悬停或固定读数不会重建无关基础序列。
- [x] AC9: 连接指标按稳定 ID 更新；日志只处理 append/drop delta；滚动期间的非关键更新有界合并且不回放积压。
- [x] AC10: 错误、断开、节点切换、延迟测试和连接关闭结果仍及时显示。
- [x] AC11: 策略组、节点、规则、来源、连接链路、拓扑内容和控制器顺序在优化前后完全一致。
- [x] AC12: controller/generation 变化后，旧投影、延后提交和工作区状态不能回写当前页面。
- [x] AC13: 自动化测试覆盖单表构造、稳定身份、日志 delta、连接 keyed update、排序冻结/提交、锚点生命周期和 generation 取消。
- [ ] AC14: 保存静态基线、离线压力和最终主机侧 SwiftUI 性能对比证据，且不接触真实控制器或系统网络。
