# Technical Design: Connection, Source And Log Workspaces

## Decision Summary

保留三页现有的单棵原生 `Table`、页面投影缓存、滚动恢复、同窗口 inspector
和控制器操作边界，只重构扫描层级和选择驱动交互：

- 连接页增加真实链路焦点区，唯一精确规则和精确策略组可跨页导航；
- 连接和来源移除独立操作列，选择后的焦点区承载上下文命令；
- 来源页增加来源生命周期焦点区，批量操作仍位于命令栏；
- 日志页采用稳定时间/级别定位栏、窄语义色轨和消息优先层级；
- 首页与管理页只接受共享原语所需的一致性修复。

不新增第三方依赖、AppKit Table 桥接、控制器 API、mock 数据或旧 UI 兼容层。

## Existing Boundaries To Preserve

| Surface | Existing source of truth | Required treatment |
|---|---|---|
| Connection rows | `WorkbenchConnectionProjectionCache` | 保留结构/指标分离、滚动期间排序冻结和稳定身份 |
| Connection mutations | generation-owned `AppModel` close operations | 继续 capability、controller ID、generation 和确认门控 |
| Source rows | `WorkbenchSourceProjectionCache` | 保留来源数据、过滤、排序和仅按声明输入重投影 |
| Source operations | provider task slot and Update All progress | 单项、批量、健康检查和重载不得竞争或伪造结果 |
| Log rows | `WorkbenchLogProjectionCache` | 保留 append/drop delta、来源顺序和稳定 ID |
| Log following | `WorkbenchLogFollowCadence` and workspace anchor | 手动滚动/选择停止跟随，Jump 恢复跟随 |
| Workspace state | `WorkbenchWorkspaceStore` | 保留搜索、排序、选择、锚点和 generation 清理 |

## Source Layout

- `WorkbenchConnections.swift`：连接焦点投影、规则/策略导航解析、Table 和
  inspector。
- `WorkbenchSources.swift`：来源焦点投影、选择驱动操作、Table 和 inspector。
- `WorkbenchLogs.swift`：日志严重度投影、色轨、跟随状态、Table 和 inspector。
- `WorkbenchWorkspaceStore.swift`：新增 generation-bound 的待处理规则导航，
  复用现有连接导航的 stage/consume 结构。
- `WorkbenchWorkspaceView.swift`：向连接页传递 destination binding。
- `WorkbenchVisualSystem.swift`：只复用已经存在的轻量路径步骤、连接符和 readout；
  页面专属色轨与投影留在各自文件。
- `Localizable.xcstrings`、聚焦测试和源码验证器同步更新。

不为每个小组件拆新文件，也不把三页重新合并为大型通用页面。

## Connections Workspace

### Selection Focus

仅在 `selectedRow` 存在时生成轻量 `ConnectionFocusProjection`。焦点区顺序为：

`连接身份/主机 → 规则类型与 payload → provider/策略链 → 目标`

每一步显示控制器真实值；缺失段明确显示未报告，不补造路径。右侧 readout 显示
已有上传、下载、速率和开始/关闭时间。活动连接按能力提供关闭当前连接和关闭
同组连接；关闭全部仍在命令栏。焦点区、Table 和 inspector 是同级区域，不包裹
或重建 Table。

### Policy Navigation

点击某个链路步骤时，仅在当前可见 arranged policy groups 中执行大小写敏感的
精确名称匹配：

1. 无匹配时只显示文本；
2. 唯一 occurrence 命中时，使用 `ProxyWorkspaceProjection.opening` 保留该组
   已有过滤和检查选择；
3. 更新 `.proxies` workspace 后切换 destination。

`DIRECT`、`REJECT`、普通节点和未知步骤不推断为策略组。

### Rule Navigation

连接页不复制完整规则投影。点击规则步骤时仅把 controller ID、generation、
原始 type 和 payload 写入新的 `WorkbenchRuleNavigationSelection`，然后切换到
Rules。Rules 页在自己的 `allRows` 中执行大小写敏感的 `(type, payload)` 精确
匹配：

- 恰好一个命中时消费请求、必要时清除阻挡目标显示的规则搜索文本、选择并滚动
  到该行；排序保持不变；
- 零个或多个命中时不生成动作，连接页在点击前即可通过轻量目录值判断为不可
  导航；
- controller ID 或 generation 变化后请求失效并由 session 清理移除。

这样导航不在连接滚动热路径构造第二份规则行，也不会用来源顺序首项解决歧义。

## Sources Workspace

仅在有选择时生成 `SourceFocusProjection`：

`来源名称 → 来源种类/内容规模 → 最近更新/健康状态`

焦点区右侧按真实能力显示单项更新和健康检查；正在执行时在固定命中区域显示
原生进度。Update All、重新加载及批量进度继续留在命令栏/其下的进度区域。

Table 移除 action column，保留名称、配置、内容规模、更新时间和状态。inspector
保留完整配置、状态、测试 URL、订阅信息、错误和最近结果，但不重复主要命令。
焦点投影只读取选中行，不遍历或格式化整个来源目录。

## Logs Workspace

`WorkbenchLogRow` 在投影阶段预计算稳定严重度枚举，SwiftUI 行 body 不重复归一化
字符串。严重度决定：

- 3 点固定宽度、低饱和度的语义色轨；
- 单色 SF Symbol；
- 明确本地化级别文字和 VoiceOver 值。

full 模式固定时间/级别定位栏，消息/载荷占主要宽度；compact 合并时间与级别但
仍把消息放在主列；stacked 使用单个完整复合列。所有模式保持固定行高、单行
扫描和完整 inspector，不使用彩色行背景、徽章、动画或嵌套卡片。

Follow Newest 在命令区显示稳定开关状态；只有停止跟随且存在更新位置时才显示
Jump to Newest。色轨和选择不得改变日志来源顺序或跟随状态。

## State, Invalidation And Performance

- 三页继续各自构造一棵 Table；宽度模式只改变该 Table 的列。
- 焦点投影只对当前选中行生成，不进入 row body，不观察无关实时域。
- 连接规则/策略解析只在结构修订或点击时进行；指标帧不重建解析目录。
- 来源操作状态只使焦点区和命令区更新，不触发静态来源搜索索引重建。
- 日志严重度随新增行格式化一次；append/drop delta 不回退为全 ring 扫描。
- 所有待处理导航和延迟操作都验证 controller ID 与 generation。

## Localization And Accessibility

- 新增英文与简体中文的连接路径、来源焦点、日志级别轨、跨页导航和命令文案。
- 路径连接符和色轨对 VoiceOver 隐藏；文字步骤、级别文字和完整值按阅读顺序
  暴露。
- 图标命令都有本地化 help、accessibility label/value 和至少 44 点命中区域。
- 截断的连接、规则、链路、来源和日志值通过 help 与 inspector 提供完整可选择
  文本。

## Compatibility And Rollback

- 不迁移 controller DTO、domain model、operation contract 或持久化 schema；新增
  待处理规则导航是 session-bound，不进入持久化编码。
- 现有搜索、排序、选择和锚点继续可读；删除的 action column 不保留双实现。
- 三页可按 Connections、Sources、Logs 分阶段回退，投影缓存与控制器操作层
  不随视觉回退改变。

## Verification Strategy

- 纯模型：连接焦点投影、唯一规则匹配、策略组精确匹配、来源焦点投影、日志
  严重度映射。
- 导航：generation 门控、歧义拒绝、目标选择/滚动、规则搜索揭示、策略组状态
  保留。
- 操作：关闭、更新、健康检查、Update All、重载和 Follow Newest 行为不变。
- 性能：单 Table、固定行高、delta 日志、keyed 连接指标、选中行限定投影和
  不可见页面无昂贵工作。
- 最终集中运行 Swift build/test、源码契约、本地化 JSON、HIG 和 diff 检查；
  不运行 runtime smoke，不连接真实控制器或 9090。
