# Proxies 源码职责拆分

## Goal

在不改变 Proxies 页面、控制器数据顺序、策略切换、会话 generation、滚动调度或本地工作区状态的前提下，将 `WorkbenchProxies.swift` 收敛为页面根组合，并把交互调度与纯投影/缓存迁移到明确的职责文件。同时删除上一轮 UI 替换后已证明不可达的旧目录、工作区和 Inspector 私有 View 岛，避免将死代码继续搬入新结构。

## Confirmed Facts

- 当前 `WorkbenchProxies.swift` 为 3,810 行；`WorkbenchPolicyGroupsView` 位于文件开头并在当前生产路径中组合 `ProxyPolicyGroupPanel`。
- `ProxyCompactGroupDirectoryHeader` 至 `ProxyNodeVerbatimDetailField` 构成连续的 12 个 `private View` 类型。它们只在该私有岛内部互相引用，当前生产源码、测试和源码验证器均不引用这些入口。
- 已归档的 `workbench-native-visual-rebuild` 明确以“单一纵向策略组流”替换“目录 + Inspector”布局；当前 `WorkbenchProxyGroupPanels.swift` 是实际的展开组、节点矩阵和行内详情实现。
- `ProxyWorkspaceLayoutMode`、`ProxyMasterDetailMetrics` 和 `ProxyOpenPathRibbonProjection` 只服务已替换布局或对应的陈旧测试/源码断言，不属于当前生产路径。
- `ProxySessionPresentation` 之后的当前文件同时包含会话呈现、catalog revision、延迟提交协调器、滚动交互 modifier、投影记录、索引、缓存、工作区 reconciliation 和顺序/过滤逻辑。
- `ProxyProjection` 与 `ProxyWorkspaceProjection` 也被 Connections、Rules 和测试使用，拆分只能改变源码所有权，不能改变 internal API、类型名称或行为。
- Workbench 目录采用精确文件清单；新增文件必须同步 `workbench-ui-contract.md`、`expectedWorkbenchFiles` 和按文件读取的 verifier 断言。
- 当前 worktree 含用户未提交修改，尤其是 Overview 对 UI contract 和 verifier 的修改；本任务必须在其上追加，不能回退或覆盖。

## Requirements

### R1. Source ownership

- `WorkbenchProxies.swift` 只保留 `WorkbenchPolicyGroupsView`、页面状态、AppModel intent、当前纵向策略组流和根级缓存协调。
- 现有 `WorkbenchProxyGroupPanels.swift` 继续拥有展开组面板、节点 tile、延迟分布和行内详情，不按小组件继续拆文件。
- 新增 `WorkbenchProxyInteraction.swift`，拥有 catalog update revision/classification、presentation coordinator/scheduler、scroll interaction tracker 和 modifier。
- 新增 `WorkbenchProxyPresentation.swift`，拥有 session/operation presentation、catalog/index/cache、workspace reconciliation、member/detail projection、排序/过滤和 mutation target 解析。
- 只将跨文件实际需要的声明从 `private`/`fileprivate` 放宽为 module-internal；leaf implementation 保持私有。

### R2. Remove superseded private UI

- 删除从 `ProxyCompactGroupDirectoryHeader` 到 `ProxyNodeVerbatimDetailField` 的不可达私有 View 岛，不将其移动到新文件。
- 删除只服务旧 master-detail/ribbon UI 的 `ProxyWorkspaceLayoutMode`、`ProxyMasterDetailMetrics` 和 `ProxyOpenPathRibbonProjection`。
- 删除或调整只验证这些旧类型的测试和 verifier 断言；不得削弱当前纵向策略组、完整节点字段、投影缓存、顺序和能力门控合同。

### R3. Preserve behavior and data contracts

- 保持 `WorkbenchPolicyGroupsView` 和 `ProxyPolicyGroupPanel` 的 View identity、输入、状态所有权与 intent 调用不变。
- 保持 Mihomo 配置顺序、其他控制器报告顺序、可见 GLOBAL 置尾、组内成员顺序、多组展开、每组过滤和关闭组释放索引的语义。
- 保持 stale/paused/unsupported/empty/filter-empty 状态、controller ID + generation 校验、capability/selectable 门控和 confirmed-write 行为。
- 保持滚动/瞬时交互期间延迟 catalog presentation、关键操作结果优先发布和最新更新不丢失的调度语义。
- 不修改 UI 布局、文案、本地化 key、AppModel/MicaCore API、持久化、网络、刷新节奏或性能算法。

### R4. Executable contracts

- 更新 Workbench 精确文件架构及 Proxies ownership 说明。
- verifier 分别读取 root、panels、interaction 和 presentation 文件，并对每个文件的所有权作正反断言。
- 保留并运行当前 Proxy projection/workspace/ordering/interaction 测试；移除仅验证已删除 master-detail geometry 的陈旧测试。
- 完整回归必须覆盖依赖 `ProxyProjection`/`ProxyWorkspaceProjection` 的 Connections 和 Rules 消费者。

## Acceptance Criteria

- [x] AC1：`WorkbenchProxies.swift` 只包含当前 Proxies 根页面组合，不再包含 coordinator、scheduler、projection/cache 声明或旧私有 UI 岛。
- [x] AC2：`WorkbenchProxyInteraction.swift` 独占 catalog presentation/scroll interaction 调度；`WorkbenchProxyPresentation.swift` 独占纯呈现模型、索引、缓存和 projection。
- [x] AC3：12 个不可达旧 View 以及 `ProxyWorkspaceLayoutMode`、`ProxyMasterDetailMetrics`、`ProxyOpenPathRibbonProjection` 从生产源码消失，陈旧测试/断言同步删除。
- [x] AC4：源顺序、GLOBAL 位置、成员顺序、多展开、独立过滤、缓存释放、SMART/report metadata、切换与测试门控保持不变。
- [x] AC5：catalog revision、滚动延期、关键结果优先、controller ID/generation 和 stale presentation 合同保持不变。
- [x] AC6：Workbench 精确文件清单、verifier 聚合与文件所有权断言同步到新结构且不弱化现有业务断言。
- [x] AC7：定向 Proxy 测试、source verifier、Swift build、完整 Swift tests、localization JSON、`git diff --check` 和 Trellis validate 通过。

## Out Of Scope

- 不重新设计 Proxies 的布局、样式、动画、可访问性、文案或交互。
- 不修改 Connections、Rules 或其他页面；它们只作为共享 projection 消费者参与回归验证。
- 不修改控制器 API、DTO、capability、AppModel 操作、session runtime、workspace persistence 或本地化资源。
- 不拆分其他大文件，不重构 verifier 的全局结构，不新增 package。
- 不启动 Mica、不访问真实控制器、不运行 runtime smoke，不创建或推送 Git commit。

## Key Decisions

- 采用 feature-local 的 root / panels / interaction / presentation 四个职责文件，不增加 Swift package 或一组件一文件结构。
- 已替换且不可达的旧 UI 直接删除；搬迁死代码会保留错误的维护表面，也违背当前 Workbench 合同“替换旧测试/类型而非保留兼容类型”的要求。
- 本任务是源码所有权和死代码清理，不以行数目标驱动，也不顺带调整现有行为。

## Risks And Deferred Items

- 跨文件后原 `fileprivate` 字符串 helper 不能继续共享；实现时使用唯一的 Proxies module-internal helper 名称，保持原始非空判断语义。
- `ProxyProjection` 和 `ProxyWorkspaceProjection` 有跨页面消费者，因此即使移动内容完全机械，也必须运行完整测试套件。
- 自动检查只能证明编译、投影和源码合同不变；由于无视觉修改，本任务不要求新的 HIG 或真实控制器验收。
