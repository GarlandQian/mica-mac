# Diagnostics 当前状态与方向研究

## 结论摘要

现有 Diagnostics 的主要问题不是某个间距、颜色或图标，而是产品信息架构仍然以实现清单为中心。页面把端点健康、试用流程、检查记录、能力矩阵、数据覆盖、可观测性和导出策略并列成八组折叠区，要求用户自己把这些技术事实重新拼成“是否可用、哪里有问题、影响什么、下一步做什么”。

建议把 Diagnostics 定义为**问题判断与处置工作台**：默认层只呈现当前结论、按影响排序的问题及安全动作；能力、覆盖、端点和操作记录只作为问题证据，完整机器信息进入次级“技术详情/复制报告”。这会改变可见投影和页面结构，但不需要废弃现有底层诊断数据与安全导出能力。

## 研究范围与边界

- 审查了 Diagnostics 根页面、展示投影、共享组件、端点检查、健康快照、能力/覆盖/可观测性和诊断导出链路。
- 审查了现有 Workbench UI 合约、父任务设计和相关投影测试。
- 回看了 Trellis 会话记录；只发现旧设计已完成的记录，没有找到用户对 Diagnostics 首要任务的明确确认。旧方案因此只能视为历史实现，不能继续当作产品前提。
- 参考了 Apple 官方诊断和界面反馈模式。外部资料用于确认交互原则，不用于照搬视觉。
- 未启动 Mica、未连接控制器、未执行远程动作；当前结论来自源码、规格、测试和官方资料。

## 当前信息架构

当前页面的默认路径是：

1. 命令栏：健康状态、兼容性，以及三个并列复制命令。
2. 结论区：控制器健康、连接、兼容性、最后检查、通用下一步。
3. 详细检查：八组默认收起的 disclosure。

八组详情分别是：

| 可见分组 | 实际数据职责 | 问题 |
| --- | --- | --- |
| Controller metadata | 当前控制器、类型、端点、版本、模式、健康 | 与顶部结论重复，机器事实优先级过高 |
| Endpoint results | 基础和增强端点健康 | 是证据，不是用户任务；缺少影响与动作映射 |
| Troubleshooting steps | profile、连接测试、快照、provider update、delay test、关闭连接、复制报告 | 混入操作历史、具有副作用的操作和报告复制，不是统一的“排障步骤” |
| Check history | 与上述步骤相近的 current/latest/last/next/retry/evidence | 与排障步骤重复，用户需要自行比对两套表述 |
| Capabilities | API/功能能力支持 | 能力门控很重要，但“不支持”不等于故障 |
| Data availability | 按产品区域重新聚合能力 | 与能力矩阵重复，仍不能直接说明用户影响 |
| Monitoring status | 快照、命令日志、报告、流 UI、流能力 | 混入内部实现完备度，不等于控制器健康 |
| Copy/export policy | 导出边界 | 支持场景的重要次级信息，不应与故障处置同级 |

源码锚点：

- `WorkbenchDiagnostics.swift:11`：所有详情默认收起。
- `WorkbenchDiagnostics.swift:95`：命令栏同时暴露三种复制动作。
- `WorkbenchDiagnostics.swift:213`：首屏仍以结论带和事实网格组织。
- `WorkbenchDiagnostics.swift:238`：八个同级详情分组连续排列。
- `WorkbenchDiagnostics.swift:487`：连接、兼容性、检查时间被固定为三个摘要事实。
- `WorkbenchManagement.swift:8`：通用管理画布最大宽度为 1180pt。
- `AppModelEndpointChecks.swift:19`：所谓“排障步骤”包含 provider update、delay test、关闭连接和复制报告。
- `AppModelEndpointChecks.swift:101`：检查记录再次投影同一组准备度和操作结果。
- `AppModelReadiness.swift:133`：能力矩阵描述的是功能/API 支持。
- `AppModelReadiness.swift:578`：数据覆盖又按产品区域聚合能力状态。
- `AppModelReadiness.swift:761`：可观测性混合数据快照、命令日志、报告和流 UI 完备度。
- `ControllerHealthModels.swift:308`：健康摘要目前只按基础端点失败、任一增强端点失败或全部通过归为 error/partial/ready。
- `AppModelDiagnostics.swift:224`：复制报告包含大量适合支持人员、但不适合默认 UI 的机器聚合。

## 根因分析

### 1. 页面呈现的是诊断系统，而不是诊断结果

当前顶层分组按代码所有权和数据来源命名。用户看到的是“能力状态”“数据可用性”“监控状态”“检查记录”，而不是“连接失败”“实时数据已暂停”“策略页面会受影响”。这会把解释责任转移给用户。

### 2. 多个模型表达同一事实，却没有统一问题投影

能力矩阵、数据覆盖和可观测性都在不同层次回答“某类数据/功能是否存在”。端点流程和检查记录也高度重叠。展示层目前主要做不可用项过滤和机器字段过滤，没有形成稳定的 `issue -> impact -> evidence -> action` 模型。

### 3. 健康摘要粒度过粗

基础端点和增强端点可以给出 ready/partial/error，但不能独立表达：

- 当前会话是 live、stale reconnecting、paused 还是 failed；
- 某项是控制器本来不支持，还是应该支持但取数失败；
- 失败影响 Overview、Connections、Rules、Sources 或操作能力中的哪些页面；
- 最近一次安全检查与当前实时状态是否仍然一致。

因此“兼容性 + 健康 + 连接”三个并列标签仍需要用户自己解释。

### 4. 默认层同时服务普通用户和开发/支持人员

三个复制命令、端点列表、能力矩阵、覆盖聚合和 observability readiness 更接近 QA/支持控制台。正常用户只需要知道当前是否有需要处理的项目；高级用户需要的是可追溯证据和安全报告。把两种任务放在同一层，导致正常状态空泛、异常状态冗长。

### 5. 视觉失衡是结构问题的结果

1180pt 的通用画布配合窄列事实、八个折叠标题和大量 hairline，在宽窗口形成稀疏横向空白，在窄窗口形成过长纵向路径。单纯放大字号、图标或容器会让这套结构更松散，不能改善扫描顺序。

## 官方模式研究

### Apple Wireless Diagnostics

Apple 的无线诊断先分析连接，再展示检测到的问题和可能的解决办法；每项可以按需查看详情。它明确说明诊断不会改变网络设置，并把压缩技术文件定位为提供给网络管理员、服务商或 IT 支持的材料。

对 Mica 的启示：

- 默认输出应是“问题 + 可能的解决办法”，而不是完整检查枚举。
- 被动诊断不应借机执行会改变远端状态的操作。
- 技术报告应与主要判断分层，服务于支持场景。

来源：[Use Wireless Diagnostics on your Mac](https://support.apple.com/guide/mac-help/use-wireless-diagnostics-mchlf4de377f/mac)（访问于 2026-08-09）。

### Apple Diagnostics

macOS Tahoe 26 及之后的 Apple Diagnostics 会让用户选择具体诊断，而不是默认执行所有检查；完成后先展示结果，参考代码用于进一步解释和服务交接。

对 Mica 的启示：

- 若需要主动检查，应按目标触发，例如“连接与身份”“数据可用性”“实时流”，而不是把所有安全和有副作用的操作组成一次总流程。
- 结果先于证据；稳定的问题标识可以用于报告和支持，但不必占据主页面。

来源：[Use Apple Diagnostics to test your Mac](https://support.apple.com/en-us/102550)（页面更新于 2025-12-19，访问于 2026-08-09）。

### Apple HIG

Apple HIG 的反馈原则强调让用户知道正在发生什么、操作结果是什么、下一步能做什么；disclosure 用于显示与当前对象相关的附加信息。它支持把状态、动作和结果放在默认层，把证据放在按需展开层。

来源：[Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)、[Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)（访问于 2026-08-09）。

## 候选产品模型

| 模型 | 默认页面 | 优点 | 代价 |
| --- | --- | --- | --- |
| A. 完整技术检查台 | 保留能力、端点、覆盖、观测和记录，只重排视觉 | 高级用户一次看到全部内部状态，改造风险较低 | 继续要求用户解释技术事实，无法解决内容不满意 |
| B. 纯问题列表 | 只显示有问题的项目和动作，全部技术信息仅在报告 | 最简洁，异常扫描最快 | 正常时信息过少，高级用户缺少可浏览证据 |
| C. 行动优先的双层工作台 | 默认显示结论、问题、影响和动作；健康范围简要汇总；技术详情次级展开 | 同时覆盖普通判断和高级排障，复用现有底层数据 | 需要新增统一问题投影，并重新定义旧测试/规格 |

**用户已确认选择 C。** 它不是在同一页继续堆两套内容，而是明确两个层级：

- 第一层服务“现在要不要处理，以及去哪里处理”。
- 第二层服务“为什么得出这个结论，以及如何交给支持人员”。

## 建议的默认页面骨架

1. **状态与检查控制**：当前控制器、当前结论、状态时间；只保留一个主检查/刷新入口。复制动作收进次级菜单。
2. **Needs Attention**：仅在存在真实问题时出现，按严重度与用户影响排序。每项包含现象、影响页面/能力、证据时间，以及一个首选安全动作或目标页跳转。
3. **Available Now**：用紧凑的产品区域摘要说明当前可用范围，不渲染几十行绿色成功项；不支持但符合控制器类型预期的能力不进入问题列表。
4. **Technical Details**：按问题关联展示端点、版本、会话、能力和最近检查证据；避免八组并列折叠和折叠内再折叠。
5. **Support Report**：单一 Copy Report 命令，并清楚说明凭据安全边界。端点结果和检查结果可作为报告内容，不再各占一个顶层复制按钮。

## 建议的数据模型边界（待设计阶段细化）

新增纯展示/领域投影，而不是让 SwiftUI 现场拼装结论：

```text
DiagnosticsSnapshot
  overallState
  freshness
  issues[]
    severity
    title/detail
    affectedDestinations[]
    evidence[]
    primaryAction?
  availableAreas[]
  technicalSections[]
  checkedAt
```

关键推导规则：

- 会话状态、端点健康、能力与实际数据可见性分别保留，不互相冒充。
- `unavailable` 只有在该控制器/能力契约本应提供且当前失败时才成为问题；固有不支持只进入技术说明或完全省略。
- 陈旧数据必须携带 freshness，不能与 live 成功状态合并。
- 最近操作失败只在仍影响当前用户任务时成为问题；复制报告、关闭连接等操作历史不参与总体健康。
- 所有修复动作继续经过 capability、controller ID 和 session generation 门控；没有安全动作时只提供导航或说明。

## 规格与测试影响

- `.trellis/spec/frontend/workbench-ui-contract.md:184`、`:403` 和 `:547` 明确锁定旧“status band + outline + fact grid”结构。已确认的新方向需要同步更新这份可执行 UI 合约。
- `Tests/MicaTests/WorkbenchManagementProjectionTests.swift:273` 起的测试锁定旧字段过滤与分组投影。应改为验证问题推导、固有不支持过滤、影响映射、freshness 和动作门控。
- 源码结构校验还要求旧 disclosure、endpoint workflow、summary fact grid 和 metadata grid。实现计划必须显式更新这些断言，不能为了通过验证而保留已被否定的信息架构。
- 诊断报告的凭据安全与脱敏测试属于不变量，应保留并作为重构边界测试。

## 最终产品决定

- 采用行动优先的双层工作台，技术事实进入次级详情与安全报告。
- 采用 live session 自动结果与一次只读立即重检，不建立独立诊断会话。
- Diagnostics 只提供重检、恢复本地展示、编辑、导航和复制报告，不直接执行远端修复。
- 采用专用自适应 master-detail：有问题时宽窗口显示问题列表与选中问题详情，窄窗口顺序展开；健康状态使用单栏摘要，不渲染空详情栏。
