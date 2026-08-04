# Workbench 全页面原生视觉重构设计

## 1. 设计结论

Mica 是面向高频扫描、筛选和操作的原生 macOS 专业工具，不是卡片式仪表盘或移动端放大版。重构采用五类页面原型，并共享窗口 chrome、导航、语义色、字号、状态和命令原语；不再用一个万能容器统一所有页面。

| 决策 | 结论 |
|---|---|
| UI 技术 | 保持 SwiftUI；AppKit 仅保留现有窗口生命周期、外观和系统集成边界 |
| 产品色 | 沿用 `MicaStyle` / Workbench 的 Midnight Instrument 语义色，不增加第二套主题 |
| 导航 | 保留 10 个一级入口，按工作台、控制器管理分组；应用偏好只在原生 Settings scene |
| Liquid Glass | 仅使用系统窗口、工具栏、侧栏和原生控件提供的效果；内容层不加自定义玻璃 |
| 图表 | 使用系统 Swift Charts 和现有拓扑实现，不新增图表包 |
| Settings | 仅保留 SwiftUI `Settings` scene 的单页 grouped Form；不增加工作台入口、设置专用侧栏或 `NSWindowController` |
| 数据 | 保持真实数据、报告顺序、可选字段、能力门控和 generation 所有权 |
| 验收 | Agent 运行离线源码/测试检查；用户负责启动应用和视觉截图验收 |

通用 Skill 只提供平台原则。项目事实以当前源码、测试、`Package.swift`、`mica-controller-development` 和活动 Trellis 契约为准。通用 Skill 中面向 iOS 的 44pt 全局命中尺寸不应用到 macOS 侧栏；Mica 使用紧凑指针界面，但按钮标签和 disclosure 必须覆盖完整可见行。

## 2. 架构边界

### 2.1 保留的数据流

控制器响应和实时流继续按以下路径工作：

`MicaCore transport/model -> generation-owned AppModel/session -> presentation projection/cache -> Workbench view`

- 不在 View 内解码、排序大型集合、发起网络请求或构造业务数据。
- 不修改控制器协议、DTO、认证、刷新和重连语义。
- 异步操作继续验证控制器 ID 与 session generation。
- 高频数据继续通过窄化 presentation state 发布；页面只观察实际渲染字段。
- 视觉重构不重新引入已删除的 command palette、旧导航或兼容包装层。

### 2.2 文件所有权

- `WorkbenchChrome.swift`：目的地、侧栏、窗口级控制和底部状态栏。
- `WorkbenchVisualSystem.swift`：语义色、字号、间距、状态、命令栏和可复用视觉原语。
- `WorkbenchDashboard.swift`、`WorkbenchOverview*`：Overview 模块、图表、拓扑和个性化。
- `WorkbenchProxies.swift`：策略组数据投影、展开状态、过滤和操作门控。
- `WorkbenchProxyGroupPanels.swift`：策略组信息带、延迟分布、节点矩阵和组内详情。
- `WorkbenchDataShared.swift` 与 Connections/Logs/Rules/Sources 文件：原生数据浏览器。
- `WorkbenchManagement.swift`：Controllers、Configuration、Actions、Diagnostics、Settings 与共享管理布局。
- `Localizable.xcstrings`：所有可见英文和简体中文文案。

按已有文件职责重构，不创建一组件一文件的碎片，也不把所有页面重新并入巨型通用 View。

## 3. 共享视觉系统

### 3.1 窗口与导航层

- `NavigationSplitView` 仍是唯一顶层导航；侧栏列表保留系统材质和滚动行为。
- 两个分组标题弱化，目的地行采用单色 SF Symbol、主文字、低饱和选中底色和细前导标识。
- 整行作为同一个 Button label 和 `contentShape(Rectangle())`，避免只有图标或文字可点击。
- 行高来自文字、图标和垂直 padding，不设置跨应用固定 44pt 规则。
- 工具栏只保留当前页面高频命令；次要动作进入原生命令菜单。底部状态栏只显示一次会话状态和最近结果。
- 菜单命令保持原生 App/File/Edit/View/Window/Help 结构和现有快捷键；自定义 Controller 菜单的语言必须跟随实际标准菜单语言，不能独立跟随内容语言造成混用。

### 3.2 内容层

- 页面底色、表格底色和提升层全部来自 Midnight Instrument 自适应 token，禁止系统白块或局部主题色带。
- 内容区不使用渐变装饰、自定义 blur、`.glassEffect`、卡片套卡片或连续浮动面板。
- 分隔线和间距建立层级；只有确实独立的工具、重复项和原生 grouped Form section 使用有边界容器。
- 标题大小与容器职责匹配；指标使用等宽数字，控制器原始文本只在数据字段中使用等宽设计。
- `AppFontScale` 只经 `micaFont` 改变语义文字点数。窗口、侧栏、工具栏、表格和点击区域不乘字号倍数；响应式布局仅由可用宽度决定。

### 3.3 状态系统

统一区分：首次加载、真实空数据、筛选为空、不支持、断线失败、暂停、保留旧数据。状态覆盖其所属内容区域，不改变命令栏或表格几何。全页空状态在剩余内容区域居中；表格状态只覆盖表格 viewport。

状态文案必须说明用户当前能做什么，不能用 API 路径、机器键值串或重复标题作为说明。断线时保留数据明确标为过期，不继续显示为实时。

## 4. 页面原型

### 4.1 Overview：可个性化监控台

- 第一视口使用上传、下载、活动连接三张等权主图表；宽窗三列，中窗两张流量图并排且连接图通栏，窄窗单列。内存只作为连接图上下文，不单独占用图表。
- 图表使用控制器真实、有限长度样本。统一 hover、点击固定、键盘步进、暂停和返回实时交互，并提供无障碍数值描述。
- 默认模块仅保留图表、完整连接拓扑和网络信息；仪表条与运营摘要保留在个性化编辑中但默认隐藏。
- 低于约 1000 点时沿用逐 mark Swift Charts；只有实际密集数据超过阈值并经测量后才考虑系统 vectorized plots。
- 完整连接拓扑保留所有真实链路。宽度适配窗口，不嵌套横向滚动；高度随最密列增长。hover/pin 高亮完整轨迹，节点优先命中，点击进入 Connections。
- 网络信息按语义分组为字段墙，保留完整真实字段，不做装饰卡片。
- 模块按可见性 lazy 构建；隐藏模块不投影、不格式化、不创建 Chart 或拓扑。

### 4.2 Proxies：有序策略选择工作区

- 使用单一纵向策略组工作区；每组由紧凑信息带、真实延迟分布和内联 disclosure 组成，整体限制阅读宽度且不产生横向滚动。
- 控制器报告顺序是唯一普通组顺序；可见 GLOBAL 始终追加在末尾。
- 支持多组保持展开，只为展开组构造缓存节点索引；每组保留独立过滤和详情选择。
- 节点使用按宽度自适应的紧凑矩阵，显示名称、类型、传输、来源、SMART 使用频率、可用性、延迟和当前选择；点击主体沿用现有切换门控。
- 节点详情在所属组内展开，以人类可读字段分组；已分类字段不在附加字段重复，附加对象和数组使用稳定紧凑 JSON 并默认折叠。

### 4.3 Connections / Logs / Rules / Sources：原生数据浏览器

- 每页只有一个原生 `Table`，其上是稳定的搜索、筛选、排序与页面命令区，其旁或下是同窗口检查器。
- 行使用稳定、廉价、唯一 ID；不在 `ForEach` / `Table` 行 body 内过滤、排序、聚合、拼接搜索文本或创建不稳定 identity。
- Connections：保留完整连接字段、分组关闭和单项关闭门控；无 ID 行可读但不可关闭。
- Logs：保持到达顺序、等级过滤、暂停和 Follow Newest；稳定流下不得因重复 debounce 永远无法跟随。
- Rules：选择后显示紧凑 `type -> payload -> target` 决策路径；仅精确命中可见策略组时可跳转 Proxies，用户界面不解释 `/rules` 等 API 路径。
- Sources：保留来源类型、状态、真实 metadata、单项更新和顺序 Update All；批量操作复用现有串行任务槽并只在末尾刷新一次。

### 4.4 Controllers / Configuration / Actions：管理工作区

- 使用居中、有最大阅读宽度的管理 canvas；宽屏保留信息密度，窄屏才按实际宽度堆叠。
- 控制器页使用列表 + 详情，不把编辑、删除散放在行中部；操作靠 trailing 对齐，管理选择不改变活动会话，只有显式 Use 才切换。
- Configuration 使用原生 grouped Form。说明、字段、当前值和错误靠近；端口、模式等不支持能力隐藏，危险变更使用现有确认边界。
- Actions 按操作风险和控制器能力分组。主动作清晰，次要动作降级；不支持项隐藏，进行中状态只锁定其所属任务槽。
- 所有按钮使用系统 button style 和 control size，避免每个动作都成为带背景方块。

### 4.5 Settings：原生 grouped Form

- 应用偏好只在系统 `Settings` scene 中显示，工作台侧栏和路由不重复设置入口。
- 当前仅“外观”和“路由”两组四项设置，不引入第二层设置侧栏和前进/后退历史。
- 保留 SwiftUI `Settings` scene；不引入 `NSWindowController` 或 AppKit 内容层。Mica 是普通窗口应用，不需要菜单栏应用的 activation-policy 模板。
- Form 使用 `.formStyle(.grouped)`、`.scrollContentBackground(.hidden)` 和轻量顶部 margin。滚动指示器使用系统默认按需显示，不强制常驻，也不通过隐藏掩盖错误内容高度。
- 常规宽度为左侧单行标题/说明、右侧 trailing 原生 Menu 或 segmented control；紧凑宽度才上下堆叠。
- Settings scene 使用系统标题和统一窗口底色。

### 4.6 Diagnostics：状态摘要 + 连续大纲

- 顶部是无外框的结论、控制器、连接、兼容性、最近检查和建议动作；下方是一棵连续、平坦的分层大纲。
- 控制器 metadata 使用自适应事实网格，不使用长表单。
- 一级和二级 disclosure 使用同一完整行命中、chevron、显式 transaction 和 Reduce Motion 处理；展开 subtree 不挂持续隐式动画。
- 过滤当前控制器 `.unavailable` 能力；若一个顶层组没有支持项，则整个组不渲染。
- 可见内容只显示用户可读的功能名、状态、原因和建议；API 路径、adapter evidence、原始报告和机器 `key=value` 串仅可进入安全 Copy Report。
- 展开内容为有界普通 stack，不嵌套 lazy 容器；格式化结果和 section projection 在 View 外预计算，避免展开后滚动抖动。

## 5. 性能策略

- 页面根不直接观察完整 `controllerSession`，继续消费字段粒度 presentation state。
- 高频域拆为独立子树：traffic、memory、connections、logs、topology、network facts 互不连带刷新。
- 仅值真正变化时写 observable state；滚动/geometry 回调只在阈值跨越时更新。
- 大集合先缓存搜索文本、排序键、聚合和格式化值；View body 只做 O(可见行) 轻量布局。
- 保持单一 `Table` / `List` 虚拟化边界、unary row 和稳定 ID；避免 `AnyView`、inline `.filter` 和动态 UUID。
- 图表数据有界，时间线不填充虚假零点；暂停只冻结呈现，真实 ingestion 继续。
- 不为纯视觉样式创建新的 timer、polling、网络任务或 broad environment dependency。

## 6. 可访问性与本地化

- 所有可见文字、菜单、帮助、tooltip 和 accessibility label/value 提供英文与简体中文。
- 带参数文案统一经过 `MicaStrings` 的格式化入口；禁止把 `%@`、`%d` 或位置占位符作为普通 `Text` 内容输出。
- SF Symbols 不单独承担含义；状态同时提供文字或形状。颜色使用语义 token，并在浅/深色下满足文本对比。
- 完整行按钮、表格选择、图表选择和 disclosure 支持键盘与 VoiceOver；装饰图标隐藏于 accessibility tree。
- 自定义动画尊重 Reduce Motion；系统 Reduce Transparency 下仍保持内容边界和对比。

## 7. 迁移与回退边界

- 这是视觉和 presentation 重构，不迁移协议、存储或控制器状态。每个阶段应保持现有 AppModel API 和测试 seam。
- 先统一共享 chrome/visual primitives，再迁移各页面，避免页面复制临时 token。
- Overview、Proxies、四个数据浏览器、管理页面和 Diagnostics 是独立回退点；某页出现问题时可回退该页布局，而不回退共享数据层或其他页面。
- 不新增第三方包。现有 gRPC/Protobuf 依赖只服务 sing-box 协议边界，与 UI 重构无关。

## 8. 参考边界

- Apple HIG：sidebars、lists and tables、outline views、charts、settings、search fields，作为平台行为与可访问性权威。
- Activity Monitor / Console：作为原生高密度数据扫描、命令区和检查器参考。
- OpenSurge：仅参考 macOS 专业工具的信息层级和密度。
- Zashboard：仅参考图表、拓扑和数据交互意图，不复制 Web 布局或代码。
- Sparxie：仅参考控制器功能和数据期望，不移植 Flutter/Rust 状态实现。

不引入上述项目的前端框架、源码或能力。
