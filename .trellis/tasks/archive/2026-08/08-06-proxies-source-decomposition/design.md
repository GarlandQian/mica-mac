# Proxies 源码职责拆分设计

## 1. Existing Data Flow

保持现有路径不变：

`generation-owned AppModel policy catalog -> WorkbenchPolicyGroupsView page cache -> Proxy catalog/index projections -> ProxyPolicyGroupPanel -> AppModel intents`

本任务不移动状态到新的 observable model，不增加环境依赖，也不改变 projection 的输入输出。文件拆分只让现有职责在编译单元中可定位。

## 2. Target File Ownership

| File | Ownership |
|---|---|
| `WorkbenchProxies.swift` | `WorkbenchPolicyGroupsView` 根组合、页面状态、AppModel intent、当前纵向策略组流、根级 rebuild/reconciliation 调用。 |
| `WorkbenchProxyGroupPanels.swift` | 现有展开策略组、节点 tile、延迟分布和行内详情 View；保持不变。 |
| `WorkbenchProxyInteraction.swift` | `ProxyCatalogRevision`、update/classifier、`ProxyCatalogPresentationCoordinator`、scheduler、scroll tracker 和 `proxyScrollInteraction` modifier。 |
| `WorkbenchProxyPresentation.swift` | `ProxySessionPresentation`、operation activity、catalog records/index/projection/cache、detail projection、workspace reconciliation、排序/过滤与 mutation target 解析。 |

只有 `proxyScrollInteraction` 的跨文件入口和纯 presentation 类型保持 module-internal。modifier/tracker 的实现细节、内部 cache key 等继续使用 `private`。

## 3. Mechanical Migration

迁移使用稳定声明边界，不依赖最终行号：

1. 保留文件开头至 `WorkbenchPolicyGroupsView` 结束作为 root 文件。
2. 删除紧随其后的 `ProxyCompactGroupDirectoryHeader` 至 `ProxyNodeVerbatimDetailField` 私有 View 岛。
3. 将 `ProxyCatalogRevision` 至 `ProxyCatalogPresentationScheduler` 移入 interaction 文件。
4. 将 `ProxySessionPresentation`、`ProxyOperationActivity` 以及 `ProxyLatencyScale` 至文件末尾的 active projection/cache 声明移入 presentation 文件。
5. 不迁移旧 `ProxyWorkspaceLayoutMode`、`ProxyMasterDetailMetrics` 和 `ProxyOpenPathRibbonProjection`。
6. 根文件移除 `Observation` import；interaction 文件导入 `Foundation`、`MicaCore`、`Observation`、`SwiftUI`；presentation 文件只导入其实际需要的 `Foundation`/`MicaCore`。

声明内容和相对顺序保持不变。唯一预期的语义中性改写是把跨文件 `fileprivate nilIfBlank` 改成唯一命名的 module-internal `proxyNonBlank`，并只更新存活调用点。

## 4. Dead Code Proof

- 旧 UI 岛内共有 12 个顶层声明，全部为 `private struct ...: View`。
- 岛内没有当前根入口 `WorkbenchPolicyGroupsView` 或实际面板入口 `ProxyPolicyGroupPanel` 的引用。
- 每个旧类型的仓库级引用只存在于该岛内部；Swift 的 `private` 访问控制排除了其他文件的动态构造。
- 已归档设计和实施记录明确当前 UI 已从目录 + Inspector 替换为单一纵向策略组流。

因此删除该岛不改变可达 View tree。陈旧 master-detail geometry test 和 verifier 类型存在性断言应随生产类型一起删除，而不是成为保留死代码的理由。

## 5. Contract And Test Migration

- `workbench-ui-contract.md` 的精确清单加入两个新文件，并说明 Proxies 四文件职责。
- verifier 新建 `proxyRoot`、`proxyPanels`、`proxyInteraction`、`proxyPresentation`，再组合为 `proxies` 供现有跨文件业务合同使用。
- 根页面结构断言只读 `proxyRoot`；缓存/顺序/detail 断言指向 `proxyPresentation`；调度断言指向 `proxyInteraction`。
- 增加正反 ownership 断言，确保后续不会再次把 coordinator/cache 塞回 root。
- 删除 `ProxyMasterDetailMetrics`/`ProxyOpenPathRibbonProjection` 存在性断言和 `proxyMasterDetailWidthsStayWithinApprovedBounds`；保留所有当前 workspace、projection、ordering、metadata、scheduler 和 coordinator 测试。

## 6. Compatibility And Rollback

- Swift tools 6.2、macOS 27、SwiftPM target 和 public/internal API 保持不变。
- 新文件仍属于同一 `Mica` target，不引入跨模块 ABI 或依赖变化。
- 若编译暴露遗漏的 file-private 依赖，先恢复最小 module-internal helper/access，再重跑受影响检查；不通过复制逻辑解决。
- 每个迁移切片都能按声明块回放到原文件，但不得使用 destructive Git 命令或覆盖当前 dirty worktree。

## 7. Durable Documentation

本次形成新的长期源码所有权边界，因此必须更新 `workbench-ui-contract.md`。无 UI、数据、会话、本地化或外部依赖合同变化，不修改其他 durable docs。
