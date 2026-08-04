# Logs、Rules 与 Sources 原生数据浏览器重构

## Goal

就地重构 Logs、Rules 与 Sources 三个原生数据浏览器的视觉层级、信息密度和扫描效率。继续使用现有投影缓存、单一原生 `Table`、稳定行身份、响应式列模式和同窗口 Inspector，不改变控制器、会话或操作语义。

## Requirements

### Shared browser contract

- 只修改现有 `WorkbenchLogsView`、`WorkbenchRulesView`、`WorkbenchSourcesView` 及其必要的页面内投影和测试，不创建平行页面或新的状态所有者。
- 每页保持一个原生 SwiftUI `Table` 作为主数据浏览器；加载、空数据、过滤为空、部分可用、失效和错误状态只替换表格内容区，不改变命令栏几何。
- 保持现有 full / compact / stacked 响应式模式，并在同一 `Table` 实例内切换列组合。窄窗口和四档字号下不得产生不必要的横向滚动、标签重叠或操作截断。
- 行只读取预计算投影。搜索、排序、聚合、格式化和跨集合索引不得放入 SwiftUI row body。
- 控制器集合保持原始顺序和完整数据；本地筛选或用户显式排序只能作用于展示副本。
- 继续使用 `MicaStyle`、`MicaDesignTokens`、`micaFont` 和现有 Workbench 数据浏览器原语。内容区不使用自定义玻璃、Material、装饰渐变、阴影卡片墙或超过 8pt 的圆角。
- 所有可见文本、帮助和辅助功能文案提供英文与简体中文；状态不能只靠颜色表达。

### Logs

- 日志表优先呈现接收时间、严重级别或类型和完整消息内容，形成连续事件流层级，不把每条日志包装成卡片或厚重 Badge。
- 严格保持控制器到达顺序、稳定 ID、级别过滤、文本搜索、暂停和 `Follow Newest` 行为。
- 保留 `BoundedLogBuffer` 的 2,000 条和 8 MiB 双重上限，不修改为其他容量。
- 连续流中的程序化滚动继续按最近实际滚动时间合并，最短间隔保持 0.2 秒；用户主动向上滚动或选择历史行时停止跟随，显式返回最新后恢复。
- `Trace` 过滤仅在已解析的 sing-box 会话中显示；Mihomo 与 Surge 不暴露其日志契约不存在的级别。
- 选中日志后继续在同窗口 Inspector 展示结构化字段和完整内容，不弹出普通模态窗口。

### Rules

- 规则表保留控制器报告顺序；只有用户显式选择排序时才排序展示副本。
- 宽布局明确分列显示序号、类型、载荷、目标、活动连接或命中信息和状态；compact / stacked 模式保留同等关键信息，避免把类型、序号和载荷挤成难扫描的一段文本。
- 选中规则后继续展示 `类型 -> 载荷 -> 目标` 决策路径及统计、元数据 Inspector。
- 只有与当前可见策略组名称精确且区分大小写匹配的目标可跳转到 Proxies；`DIRECT`、`REJECT`、节点名和未知目标保持只读。
- 状态与可用操作继续合并在同一尾部单元格，不恢复独立操作列，也不展示 `/rules` 等 API 或调试说明。

### Sources

- 来源表按报告顺序展示名称、类别、配置、条目数量、更新时间、能力和生命周期状态；状态使用安静的图标、点和文本，不使用大块状态卡或卡片网格。
- 选中来源后，顶部 focus rail 清晰关联当前行、生命周期和可用操作；详情继续使用同窗口 Inspector。
- `Update All` 只选择可更新来源，严格按当前报告顺序串行执行，共用现有 provider task 槽，并在队列结束后只刷新一次 catalog。
- 单项更新、健康检查和重载不能取消或竞态覆盖正在执行的批量更新；部分失败必须保留逐项结果和最终批次结论。
- 真实测试 URL、订阅元数据和缺失值语义保持现状，不伪造时间、数量、成功或能力。

## Out of Scope

- 不修改 Overview、Proxies、Connections 或管理页面的业务与布局。
- 不修改控制器 HTTP / WebSocket / gRPC、DTO、领域模型、认证、重连、刷新协调或 generation 生命周期。
- 不增加第三方依赖、页面级定时器、真实控制器访问、runtime smoke 或应用启动验证。
- 不全局修改数据浏览器固定行几何；本任务只调整三页的信息层级和页面内呈现。

## Acceptance Criteria

- [x] 每页源码仍只有一个原生 `Table`，共享命令栏、状态区、响应式列模式和 Inspector 结构保持成立。
- [x] Logs 保持到达顺序、2,000 条 / 8 MiB 上限、0.2 秒 Follow Newest 合并节奏和 sing-box Trace 门控；持续流过滤与滚动测试通过。
- [x] Rules 宽布局具有独立可扫描列，窄布局信息不丢失；原始顺序、展示副本排序、连接预索引和精确策略组跳转测试通过。
- [x] Sources 状态和 focus rail 使用扁平高密度表达；Update All 的可更新过滤、报告顺序、串行执行、单次最终刷新和竞态保护测试通过。
- [x] 英文/简体中文、四档字号及窄/中/宽布局的源码合同和本地化目录通过验证；浅色/深色像素级验收留给父任务 Cross-Surface Acceptance，按本任务约束未启动应用。
- [x] 表格行不新增全集过滤、排序、跨集合扫描或重复字符串组装；现有 projection/cache 性能计数测试继续通过。
- [x] 相关 Swift tests、源码 verifier、XCStrings JSON 校验、`swift build`、完整 `swift test` 和 `git diff --check` 通过；验证过程未启动 Mica、未连接真实控制器、未运行 runtime smoke。

## Notes

- 当前 `WorkbenchDataBrowserScaffold`、投影缓存、稳定身份和 Inspector 已满足架构边界，本任务以就地视觉重构和可扫描性改进为主。
- 当前可访问的 Midnight Instrument 自适应 palette 是仓库事实来源，不在本任务中切换为另一套硬编码颜色。
