# Mica Workbench 全局原生 UI 重构

## Goal

在不改变 Mica 控制器协议、会话语义和安全边界的前提下，系统性重构全部用户可见界面，使其成为统一、清晰、响应式且高性能的原生 macOS 27 控制工作台。用户应能在每个页面快速判断当前控制器状态、理解真实数据、完成主要操作，并在浅色/深色、四档字号和不同窗口宽度下获得一致体验。

本任务是全局需求与集成验收的父任务。页面实现按可独立验收的子任务分阶段完成，避免一次性重写造成范围失控。现有 `connections-native-visual-rebuild` 子任务继续负责 Connections 与其已纳入的 Proxies 展示修正，不重复实现。

## Confirmed Facts

- Mica 是 Swift 6.2、SwiftPM、macOS 27 原生应用；主要内容层使用 SwiftUI，AppKit 只承担应用生命周期、窗口、系统外观、剪贴板等既有平台边界。
- 主窗口有 10 个真实目的地：Overview、Proxies、Connections、Logs、Rules、Sources、Controllers、Configuration、Actions、Diagnostics。
- 独立 Settings 入口为 `Settings { MicaSettingsSceneView() }`；设置项只有语言、外观、四档界面字号和 GLOBAL 策略组可见性。
- 新增/编辑控制器使用主窗口内的 `RouterEditorView`，不是普通 Sheet；凭据继续通过现有 AppModel/Profile 存储路径进入 `FileSecretStore`，视图不得直接改写存储架构。
- `AppModel` 为 `@MainActor @Observable`，Workbench 读取细粒度 presentation/catalog/projection；页面不得建立平行数据源或自行拥有控制器连接。
- 实时发布节奏由 runtime 负责：Traffic 约 250ms、Connections 约 500ms、Memory 约 1s、Logs 约 200ms。View 不得另建定时器或二次节流链。
- `BoundedLogBuffer` 的上限为 2,000 条或 8 MiB，必须保持。
- 当前视觉合同是 `MicaStyle` / `MicaDesignTokens` 中的 Midnight Instrument 自适应语义色；它延续 Rose Pine 的柔和层次，但以当前源码中已验证的可访问色值为准。
- 原生窗口、侧边栏和工具栏可以承担系统材质；内容区不得自定义 glass、装饰渐变、嵌套卡片或普遍使用大圆角。
- 断线重连时保留最后一次成功数据并明确标记 stale；只有控制器切换、generation 结束或明确清理时才清空对应实时数据。
- 当前活动控制器报告的业务数据在界面中完整可见和可选择；凭据、授权值、订阅 URL、密钥存储内容及原始响应/流正文不得进入导出报告。

## Requirements

### R1. Unified visual and navigation system

- 全部页面复用现有 `MicaStyle`、`MicaDesignTokens`、`WorkbenchVisualSystem`、`WorkbenchSymbol` 和 `micaFont` 语义，不创建平行视觉框架。
- 主窗口、原生工具栏、命令栏、内容区和底部状态区域使用一致的自适应 page fill，消除页面之间的色带断层。
- 内容圆角不超过 8pt，原生控件与语义 badge 例外；避免“每个字段一张卡”的信息墙。
- 侧边栏保持 10 个真实目的地，整行可点击，选中态克制、清晰且支持键盘导航。
- Settings 只存在于原生 Settings 窗口；不得在 Workbench 再复制一个设置页面。
- 不恢复 Command Palette、Command Deck 或 Cmd+K 自定义面板。

### R2. Responsive layout and interaction

- 数据浏览器保持宽度填充、单一主滚动所有者和稳定行几何；管理页使用有界阅读宽度，但不能留下与窗口不成比例的空白。
- 布局断点由可用宽度决定，不由字号档位决定；字号变化不得把桌面布局意外切换成移动式纵向排版。
- 所有侧边栏行、disclosure header、表格选择行和主要命令拥有完整、可预测的点击区域，不使用全局固定 44pt 规则。
- 普通工作流在同一窗口完成；详情优先使用内联展开、SplitView 或 Inspector，破坏性操作使用 generation-safe 行内确认。
- 动画只用于短暂状态和结构变化，并在 Reduce Motion 下静态降级；不得为持续数据流添加弹簧或全树隐式动画。

### R3. Data, ordering, capability, and lifecycle correctness

- 只显示真实 `AppModel` / `MicaCore` 数据，不制造图表样本、延迟、统计、成功状态或控制器能力。
- 控制器集合顺序保持稳定。Mihomo 普通策略组遵循 `GLOBAL.all` 配置顺序，未列出组保持 `/proxies` 顺序，GLOBAL 置尾；Surge 与 sing-box 保持报告顺序；组内节点保持报告顺序。
- 所有动作通过现有 capability 和 AppModel 操作门控；未支持的业务区块应隐藏或显示统一的页面级 unsupported 状态，不能发送猜测的 API。
- 异步动作必须在提交和回收结果时校验 controller ID、session generation 与目标身份；旧确认和旧结果不能作用于新会话。
- stale、paused、disconnected、loading、empty、filtered-empty、unsupported、partial 和 failed 状态必须准确区分，不能把旧数据显示为实时。

### R4. Module outcomes

1. **Overview**：保留可个性化的真实监控台、交互式 Swift Charts、完整连接拓扑和网络信息；模块不重复业务浏览器，缺失能力时隐藏对应模块。
2. **Proxies**：保持源顺序、多组同时展开、组内过滤、真实延迟/SMART/能力字段和安全节点切换；节点与详情使用高密度、可扫描布局。由现有子任务继续完成。
3. **Connections**：使用紧凑真实概览、一个原生 Table、完整决策链和同窗口详情；活动与已关闭连接严格区分。由现有子任务继续完成。
4. **Logs**：使用高密度原生日志流，保留级别过滤、搜索、暂停和 Follow Newest；固定保留 2,000 条/8 MiB，持续流中滚动不饥饿。
5. **Rules**：保持控制器顺序的原生 Table、类型/载荷/目标检索和精确策略组跳转；不得显示 `/rules` 等调试端点说明。
6. **Sources**：使用原生 Table 展示真实来源字段；Update All 按报告顺序串行执行，完成后只刷新一次 catalog。
7. **Controllers**：使用列表加同窗口详情；只有显式 Use 操作可以切换当前控制器，不抢占已有会话、不轮询所有控制器。
8. **Add/Edit Controller**：保留同窗口编辑、输入校验、连接测试和现有凭据存储路径；不创建巨大全屏表单或重复标签列。
9. **Configuration**：根据当前控制器真实 config/capabilities 渲染可修改字段；修改继续使用既有 AppModel 操作、回滚和 generation 校验，不显示 YAML 编辑器。
10. **Actions**：只呈现当前控制器已支持的现有动作，普通列表/表单布局，破坏性动作使用同窗口确认；不得虚构端点。
11. **Diagnostics**：先给出人类可读结论，再分层展示真实检查；页面不输出 API 路径、机器键值墙或原始响应，技术细节只进入安全的 Copy Report。
12. **Settings**：独立原生 Settings 窗口，仅含语言、外观、四档字号和 GLOBAL 可见性，修改后所有窗口立即生效。
13. **Menu/Toolbar**：使用原生 macOS Commands/Toolbar，本地化一致；Toolbar 不重复侧边栏已有的控制器身份，不恢复 Command Palette。
14. **Global Shell**：保持 `NavigationSplitView`、10 个目的地和现有 AppModel/session 生命周期；切页释放昂贵可见投影但不破坏合法 stale 数据。

### R5. Performance

- 高数据量页面只让行读取预计算投影；不得在 SwiftUI row body 中做全集过滤、排序、聚合、JSON 格式化或跨集合扫描。
- Logs、Rules、Sources、Connections、Proxies 使用稳定 ID、增量 catalog revision 和 Lazy/Table 虚拟化；实时数值变化不得重建静态行。
- Overview 图表与拓扑只消费 runtime 发布的有界数据；保持既有摄取节奏，避免页面级 timer、重复 animation 和 GeometryReader 反馈循环。
- 大文件按职责拆分时先机械移动现有类型，再做视觉修改；不得创建同名平行 View 或扩大状态所有权。
- 不新增第三方包作为默认方案。只有在现有 Apple 框架或项目代码无法满足且有可测材料收益时，另行记录依赖、许可证、兼容性和边界测试后再决定。

### R6. Localization and accessibility

- 所有可见文案、菜单、help、tooltips 和 accessibility 文案通过 `MicaStrings` / XCStrings 解析，英文与简体中文完整且不混杂。
- 四档字号 `standard / comfortable / large / extraLarge` 必须明显改变所有页面文字，但不缩放窗口、侧边栏、表格、工具栏和状态栏几何。
- 数字使用稳定的 monospaced digit 语义；图表、状态、行和按钮提供可理解的 VoiceOver 标签，不只依赖颜色表达含义。

### R7. Staged delivery and review

- 每个子任务只修改其明确页面和必要共享原语，完成完整页面切片后再集中验证。
- 每个子任务包含浅色/深色、四档字号、窄/中/宽窗口、连接状态和至少一个大数据量场景的验收。
- 父任务最后执行跨页面一致性、生命周期、性能、本地化和可访问性整体验收；不得以单页通过替代全局验收。

## Acceptance Criteria

- [ ] AC1：14 个模块都在真实现有类型上完成重构，没有平行页面、重复 Settings 或恢复 Command Palette。
- [ ] AC2：全局 page fill、语义色、字体、图标、圆角和间距来自现有共享系统；内容区无自定义 glass、装饰渐变、卡片墙或色带断层。
- [ ] AC3：所有页面在窄/中/宽窗口与四档字号下无重叠、无不必要横向滚动、无固定宽度造成的大面积失衡空白。
- [ ] AC4：Overview 图表、拓扑、网络信息及所有页面数据均来自真实 catalog/session；缺失能力不显示伪数据或静态占位图表。
- [ ] AC5：Proxies 和 Connections 子任务全部验收；策略组与节点顺序、多个展开状态、连接活动/已关闭状态和完整链路保持正确。
- [ ] AC6：Logs 保持 2,000 条/8 MiB 限制；Rules 与 Sources 保持报告顺序和各自操作语义；大列表滚动与持续更新无明显卡顿。
- [ ] AC7：Controllers 只通过显式 Use 切换；RouterEditor 保持同窗口和现有凭据存储；Configuration、Actions、Diagnostics 只显示真实支持能力。
- [ ] AC8：断线重连保留并标记 stale；切换控制器或 generation 结束时不残留上一控制器实时数据；旧异步结果和确认失效。
- [ ] AC9：设置中的语言、跟随系统/浅色/深色、四档字号和 GLOBAL 可见性在所有打开窗口即时生效。
- [ ] AC10：英文/简体中文菜单、页面、状态、help 与 accessibility 无语言混杂和 `%@` 等格式占位符泄漏。
- [ ] AC11：相关 projection/state/operation 测试、源码 verifier、XCStrings JSON、Swift build、完整 Swift tests 和 `git diff --check` 通过。
- [ ] AC12：每个子任务均完成用户运行时视觉验收；父任务完成一次全页面一致性复核。自动验证不启动 Mica、不访问真实控制器、不运行 runtime smoke。

## Out of Scope

- 不新增、下载、打包、启动或管理本地代理核心。
- 不修改系统代理、网络、DNS、防火墙、OpenWrt、LuCI、SSH 或 `ubus`。
- 不重写控制器 HTTP/WebSocket/gRPC 协议、DTO/领域模型转换或会话重连策略，除非实现中发现经测试证明的现有 bug，并另行更新本任务设计。
- 不增加生成稿中虚构的启动项、菜单栏模式、快捷键编辑器、About、后台全控制器 Ping、自动故障转移、请求 Headers 检查器或 YAML 配置编辑器。
- 不以第三方 UI 框架替代 SwiftUI，不引入自定义内容玻璃，不照搬其他项目源码。
- 不在父任务规划阶段修改应用源码。

## Key Decisions

- 采用父任务加分阶段子任务，不进行一次性 14 页面大爆炸重写。
- 现有 `connections-native-visual-rebuild` 是本计划的既有子任务，先完成其质量门再推进下一阶段。
- 当前源码、测试、`Package.swift` 与 Trellis 合同优先于外部生成稿；外部 UI 参考只提供信息层级与交互启发。
- 没有阻塞规划的开放问题。运行时视觉验收由用户完成，因为本计划禁止 runtime smoke 和真实控制器访问。
