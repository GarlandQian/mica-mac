# Technical Design: Rules And Policy Decision Workspace

## Decision Summary

保留现有原生 `Table`/`List`、投影缓存、控制器 mutation 和工作区持久化，
只替换规则与策略组的呈现结构：

- 规则选择生成轻量决策路径焦点条；
- 精确匹配的规则目标通过现有目的地绑定跳转并预先打开策略组工作区；
- 策略组使用来源顺序目录、无横向滚动的打开路径带和活动组焦点条；
- 节点列表增加真实延迟比较轨道，详情改为按检查选择出现；
- 策略组页在窄窗口切换为同页上下结构。

不增加第三方依赖、AppKit 列表桥接、控制器 API 或兼容旧 UI 的包装。

## Existing Boundaries To Preserve

| Boundary | Existing source of truth | Required treatment |
|---|---|---|
| Rule rows | `WorkbenchRuleProjectionCache` | 保留静态/活跃连接分离与单棵 Table |
| Group order | `ProxyProjection.arrangedGroups` | 普通组保持上报顺序，可见 GLOBAL 最后 |
| Active members | `ProxyCatalogProjectionCache.activeGroupIndex` | 仅构建活动组成员 |
| Workspace state | `WorkbenchWorkspaceStore` | 保留打开组、过滤、检查选择和恢复 |
| Group close | `ProxyWorkspaceProjection.closing` | 继续使用下一项优先、否则上一项 |
| Mutations | `AppModel` capability-gated operations | 不绕过能力、会话或 generation 检查 |

## Source Layout

- `WorkbenchRules.swift` 保留规则投影、Table、焦点条与 inspector。
- `WorkbenchProxies.swift` 保留策略目录、工作区呈现、活动节点投影、缓存和工作区
  协调，并使用清晰 `MARK` 分区控制文件内职责。
- `WorkbenchVisualSystem.swift` 承载两页共享的轻量路径步骤和连接符；不增加
  Workbench 文件，遵守当前目录结构契约。
- 纯布局/导航/延迟比例模型靠近其唯一使用者；只有被两页复用时才进入共享区域。

这是一个单任务而非两个子任务：规则目标跳转必须与策略工作区打开状态原子衔接，
拆开会产生可点击目标已经上线但目标页无法恢复正确组状态的中间行为。

## Rules Data Flow

1. `selectedRowID` 继续由 `Table` 和 `WorkbenchWorkspaceStore` 管理。
2. 仅当 `selectedRow` 存在时生成 `RuleDecisionPathProjection`：
   类型、payload、目标、状态和已有统计全部来自该行。
3. `RulePolicyTargetResolver` 在点击时对当前控制器的 arranged group 进行精确、
   大小写敏感匹配。解析是 O(groups) 的低频用户动作，不进入 Table 行 body。
4. 命中后，用 `ProxyWorkspaceProjection.opening` 更新 `.proxies` 工作区，再通过
   `WorkbenchWorkspaceView` 传入的 `Binding<WorkbenchDestination>` 切换到
   `.proxies`。
5. opening 复用现有组状态，因此已有过滤和检查节点不被清空。未命中、
   `DIRECT`、`REJECT` 或非组目标不创建动作。

规则焦点条放入 `WorkbenchDataBrowserScaffold.supplementary`。Table 和 inspector
仍是现有结构，焦点条不会包裹或重建 Table。

## Policy Workspace Composition

### Adaptive Shell

`ProxyWorkspaceLayoutMetrics` 从可用宽度解析离散布局：

- `.split`: 目录宽度限制在 240-320 点，节点工作区使用剩余宽度，总画布保留
  现有合理最大宽度；
- `.stacked`: 顶部为紧凑目录 disclosure，下面为全宽节点工作区。

阈值由目录最小宽度、节点可用宽度、分隔线和字体环境决定并由纯模型测试覆盖，
不在多个子视图中重复判断。紧凑目录展开状态是页面本地呈现状态，不写入持久化；
选择组后自动收起，组过滤和节点检查选择仍持久化。

### Directory Hit Regions

每个目录行由两个同级控件组成，禁止 Button 嵌套：

- 主按钮覆盖组名、当前节点和元数据，只调用 open/activate；
- 尾部 disclosure 按钮只调用 open/close。

当前组再次点击主按钮只激活。两个控件分别提供辅助功能标签、状态和值。

### Open Path Ribbon

`ProxyOpenPathRibbon` 只接收已按来源顺序排列的轻量打开组：

- 可见项显示 `group → selected node`；
- 当前项使用底部 2 点强调线，不添加胶囊或块状背景；
- 使用少量有界 `ViewThatFits` 配置选择可见前缀，剩余尾部进入 `Menu`；
- 溢出菜单保持来源顺序并标记当前项；
- 关闭动作仅在悬停、键盘焦点或当前项显示；
- 不创建横向 `ScrollView`，不渲染非活动节点列表。

### Active Focus Rail

活动组焦点条替换现有普通 header，显示：

`group → controller selected node → candidates`

右侧容纳组测试、解除固定选择和操作进度。所有状态来自
`ProxyActiveGroupProjection` 与现有 capability/operation 状态，不派生新状态。

## Node Comparison And Inspection

`ProxyLatencyScale` 仅扫描活动组已投影成员中的有效正延迟：

- 轨道比例为 `delay / maximumValidDelay`，限制在可见范围；
- 无有效延迟时不创建轨道；
- 精确毫秒文本和现有语义延迟颜色始终优先；
- 比例不参与排序、搜索、身份或 mutation。

节点行使用固定几何和背景轨道，不添加动画。控制器当前节点与工作区检查节点使用
不同语义：当前节点是控制器真值，检查节点只控制详情。

详情生命周期：

1. 节点点击先更新工作区检查 ID，再按现有能力发起切换；
2. 宽窗口有检查节点时插入右侧 inspector；无检查节点时 List 占满宽度；
3. 窄窗口有检查节点时在同页底部插入详情；无检查节点时完全移除；
4. 关闭只清空检查 ID，不调用控制器 mutation，不改变 `group.selected`。

## State, Invalidation And Concurrency

- 新路径投影都是同步小值模型，不新增 Task、actor 或定时器。
- 规则目标解析只发生在点击时。
- 路径带只接收打开组摘要；高频节点延迟不得让目录搜索索引或非活动成员重建。
- 延迟比例在活动成员投影更新时计算一次，行只读取比例。
- 现有 `ProxyCatalogPresentationCoordinator` 继续负责滚动期间的最新值合并和
  generation 安全；新视图不观察完整 `controllerSession`。

## Localization And Accessibility

- 新增中英文路径、溢出、展开/收起、当前选择和候选节点文案；动态控制器值使用
  插值而不是本地化 key。
- 路径视觉箭头对 VoiceOver 隐藏，路径步骤按阅读顺序提供组合描述。
- 组主按钮、disclosure、关闭、节点切换、节点测试和 inspector 关闭均为独立
  可聚焦命令，最小命中区域遵守项目 HIG 检查。
- 截断名称通过 help 和 inspector 暴露完整值；业务数据不脱敏。

## Compatibility And Rollback

- 不迁移控制器 DTO、领域模型或工作区持久化 schema。
- 旧的打开组、过滤、节点检查选择、规则排序和选择继续可读。
- 替换旧 `ProxyWorkspaceTabs`、`ProxyActiveGroupHeader` 和常驻 inspector，
  不保留双实现或旧名称兼容层。
- 每一阶段都可通过恢复对应视图文件回退；投影缓存和 mutation 层不随 UI
  回退而改变。

## Verification Strategy

- 纯模型：精确目标解析、DIRECT/REJECT 排除、来源顺序、路径带可见/溢出顺序、
  split/stacked 阈值、延迟缺失与比例。
- 工作区：打开/激活不关闭、显式关闭、下一项/上一项选择、过滤和检查选择保留、
  inspector 关闭不改变控制器当前节点。
- 性能：单棵规则 Table、单棵活动节点 List、非活动组不构建成员、点击解析不
  进入滚动热路径。
- 最终集中运行构建、测试、source verifier、localization JSON、HIG 检查和
  `git diff --check`；不运行旧 runtime smoke，不连接真实控制器或端口 9090。
