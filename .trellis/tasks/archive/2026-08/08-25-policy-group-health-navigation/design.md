# Design: Workbench 实时链路与策略组定位收口

## 1. Boundary

不改 `MicaCore` DTO、controller endpoint 或 capability。现有 `AppModel` controller/session 层负责 lifecycle 与实时发布，Workbench 只消费其 field-granular presentation。策略组仍以 `AppModel.policyGroupCatalog` 为唯一数据源；任何恢复、定位或筛选都不能启动新的远程操作。

| Layer | Responsibility | Planned correction |
| --- | --- | --- |
| Live session | Runtime ownership, producers, refresh lanes, freshness, rate derivation | Channel/runtime 生命周期解耦、endpoint failure 隔离、单调时间和 duplicate-safe counters |
| Workspace store | Window/session-bound cross-page intent | Target 携带稳定 group occurrence ID；controller/generation 精确消费和清理 |
| Proxy presentation | Ordered indexes, health/filter/resolution | 真实 content state、非正延迟归一、Attention/Slow 语义、结构化 resolution reason |
| Proxy interaction/view | One scroll owner and explicit reveal | 单一有效 target scope、一次滚动、组合 obstruction 和 session-bound highlight |
| Overview | Topology and inspector entry points | 所有 Open Proxies 入口复用同一 staged target builder |
| Localization/tests/verifier | Durable behavior | 双语原因/动作、辅助功能名称、状态序列测试和源码约束 |

## 2. Live Runtime State Machine

`LiveSessionRuntimeIdentity(controllerID:generation:)` 继续是 actor 唯一身份。actor 只在整个 session 被替换、停止或进行受控的全流重建时 invalidated；单个 channel failure 不直接调用 `cancelLiveSessionRuntime()`。

每个 Mihomo channel 保留独立 producer task，但 retry 继续使用既有共享 reservation：

1. transient/retry-once failure 只允许一个 retry 波次；该波次先取消全部旧 producer，再安装新 actor，然后启动新 producer，不新增 channel-local retry 子系统；
2. 已预留 retry 后，来自同一批旧 producer 的后续 callback 不得重复取消、推进 backoff 或把 reconnecting 重分类为 terminal；
3. terminal channel 将聚合 live/session 状态标记为 partial（首个 baseline 前为 failed），保留 last-good 数据和 runtime，健康 sibling 继续 ingest/publish；
4. user-initiated Refresh 重启当前 controller 请求的 streams，并并行运行 REST lanes；旧 runtime identity 与旧 generation 的 completion 都被丢弃。

sing-box 和 Surge near-live 维持现有 transport，只共享 controller/generation 校验和 Refresh 恢复契约。

## 3. Refresh Lanes, Freshness, And Rates

多端点 lane 继续并发请求并先发布每个成功结果。lane completion 区分：全部成功、部分成功、全部失败。部分成功不会调用整 lane 的 terminal `finishFailure`; 失败 endpoint 自己保留 health、last-good 和下一周期重试资格。只有没有任何可用结果且该 lane 的必要边界失败时，才允许 lane-level failure。

`completeLiveTransportIngestion` 使用 `max(existingLastSuccessAt, publication.receivedAt)`；跨 domain revision 仍各自单调。

`ConnectionTransferRateTracker` 使用与 runtime/Workbench 相同的 duplicate occurrence identity。若 duplicate 不能在相邻帧稳定对应，保留 controller-reported speed 或 unavailable，不用另一个 occurrence 的 counter 猜测。

## 4. Proxy Navigation And Reveal

`WorkbenchProxyNavigationSelection` 保留 controller ID、generation、stable group occurrence ID 和 node name。Overview policy index/selection 在目标可唯一解析时产生 occurrence ID；原始 group name 只作为展示字段，不再充当精确身份。

Reveal resolver 返回结构化结果：resolved、global-visibility obstruction、global search、group query、health filter、missing group、ambiguous group、missing node、stale session。页面由该结果派生一个稳定 notice；不再把所有失败折叠为“controller no longer reports”。

一次 clear-and-locate 先计算完整 obstruction set，再原子清理 search/group/health 本地条件并重新 resolve。GLOBAL 偏好使用单独的 Show GLOBAL and Locate 明确动作；普通清理不修改全局偏好。

空 catalog 也会消费当前 generation 的 staged target并显示 missing/empty 原因。目录后续刷新时，仍有效的 unresolved target 可重新 resolve；session 替换会清理它。

## 5. Single Scroll Owner

保留 Proxies 页唯一外层 `ScrollView`。用一个 `ScrollViewReader` 包住它，节点 tile 继续拥有稳定 `.id`，但移除互相嵌套的 `scrollTargetLayout` 依赖。Resolver 先展开目标组，在同一 scroll owner 内定位 group ID 使远处 `LazyVStack` 子树 materialize，等待一帧并再次验证 token/controller/generation，再执行一次精确的 `scrollTo(targetID, anchor: .center)`。只有节点滚动实际执行后才记录完成 token；被取消的两阶段任务可由同一 reveal 重试。普通 catalog refresh 不创建 token，900 ms 高亮过期也不保留滚动锚点。

## 6. Health, Content States, And Accessibility

- Group/member controller order保持不变。
- Attention = degraded + unavailable + unknown；Unavailable 和 Slow 是诊断子集；Slow 只含 `.slow`。
- `delay <= 0` 在摘要、比例、颜色、tile 和 tooltip 中按 unavailable；完整 inspector 可保留 controller 原始字段。
- 页面根状态先判断 controller/session/capability/catalog，再判断 `visibleGroups` 与 query，明确区分 empty 和 filtered-empty。
- Locate Current Node 从当前 catalog 的 controller-selected member 推导，不读取 inspector-only selection。
- 节点测试图标按钮增加本地化 accessibility label；颜色只补充文字/状态值。

## 7. Performance And Safety

- 不增加 timer、polling loop、endpoint、package 或 view-owned network task。
- Catalog/health/index 继续在 page-owned cache 构建；SwiftUI tile body 不扫描全目录。
- Live runtime publication cadence和 destination demand mapping保持现有 200/250/500/1000 ms 与 2/5/30 s 设计。
- 所有 async apply、retry、navigate、scroll 和 mutation继续验证 controller ID + generation。
- 自动化只使用 local fixtures/in-process adapters，不读取 profile、不访问 9090、不连接 controller。

## 8. Test And Rollback Design

先添加失败测试，再改实现：channel terminal + sibling publication + manual recovery、mixed endpoint lane、cross-domain timestamp、duplicate connection IDs、topology-to-proxy staging、duplicate group identity、empty/no-match/GLOBAL、多重 obstruction、current-node source、non-positive latency、filter semantics、accessibility source contract、single-scroll reveal token。

回滚点：

1. Live channel state refactor可独立回滚，不影响 REST endpoint projection。
2. Typed occurrence target可独立回滚到 truthful unresolved，但不能恢复 first-match 猜测。
3. 两阶段同一 ScrollView 定位若运行时验证失败，降级为 inspector-only reveal，不增加嵌套滚动或恢复 `scrollTargetLayout`。
