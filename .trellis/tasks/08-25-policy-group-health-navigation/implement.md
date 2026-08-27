# Implement: Workbench 实时链路与策略组定位收口

## Status

2026-08-27 已完成 D1-D14、terminal-before-baseline 补充边界、独立 Trellis 终检与全部离线门禁。未连接真实控制器，也未执行 runtime/UI/VoiceOver smoke。

## Completed Ordered Steps

- [x] 1. 为 D1/D2 添加 live-session 失败测试：terminal channel + sibling publication、manual Refresh recovery、mixed endpoint lane success/failure；先确认测试在当前实现上失败。
- [x] 2. 重构 Mihomo channel/runtime lifecycle，使 actor session-owned、terminal domain 隔离、Refresh 可恢复；保持 sing-box/Surge generation 边界和现有 cadence。
- [x] 3. 隔离 refresh-lane endpoint failure，并修复 monotonic `lastSuccessAt` 与 duplicate-safe connection rate tracking；添加跨 domain/duplicate fixtures。
- [x] 4. 将 proxy navigation target 升级为稳定 occurrence identity；统一 Overview topology、VoiceOver、policy inspector、workspace store 和 Proxies resolver 的 staged-target builder。
- [x] 5. 重构 reveal 状态机：结构化 unresolved reason、空 catalog 消费、GLOBAL obstruction、多筛选一次清理、controller-current 定位和 session refresh reconciliation。
- [x] 6. 用单一外层 `ScrollViewReader`/有效 target scope 完成 node reveal；清理过期 scroll anchor，并覆盖 token replacement、passive refresh 和 generation switch。
- [x] 7. 修复 no-match/empty 状态、Attention/Slow 语义、非正延迟显示和节点测试按钮 accessibility label；更新中英本地化。
- [x] 8. 更新 source verifier 和 focused tests，确保无新 endpoint/package、无嵌套 ScrollView、无 first-match、无静默偏好修改、无 capability bypass。
- [x] 9. 运行 `node --check scripts/verify-real-controller-source.mjs`、`node scripts/verify-real-controller-source.mjs`、localization JSON、`swift build`、`swift test` 和 `git diff --check`。
- [x] 10. 运行两次可比 Release performance benchmark；保留达到阈值的 connection-frame 首帧快路径，确认无稳定超过 10% 的无关回归。
- [x] 11. Dispatch `trellis-check` 做独立跨层审计并修复 findings。运行时 UI/controller smoke 仅在用户另行授权后执行。

## Verification

- `swift build`: pass.
- `swift test`: XCTest 106/106；Swift Testing 333/333（27 suites）。
- Focused `LiveSessionPublicationTests`: 33/33。
- Source verifier、localization JSON、JSONL、Node syntax 与 `git diff --check`: pass.
- Release reports each contain 25 matching cases and checksums. `runtime-connection-frame@10000` measured 4.956/4.950 ms versus 6.750 ms in the prior comparable report; `proxy-catalog-index-projection@100000` measured 57.49/55.46 ms and `proxy-expanded-groups-projection@2000` measured 1.77/1.66 ms.

## Risky Files

- `Sources/Mica/App/AppModelLiveSession.swift`
- `Sources/Mica/App/AppModelLiveSessionRuntime.swift`
- `Sources/Mica/App/LiveSessionRuntime.swift`
- `Sources/Mica/App/LiveSessionRefreshModels.swift`
- `Sources/Mica/App/OperationSessionModels.swift`
- `Sources/Mica/Features/Workbench/WorkbenchOverviewTopologyView.swift`
- `Sources/Mica/Features/Workbench/WorkbenchOverviewPolicyInspection.swift`
- `Sources/Mica/Features/Workbench/WorkbenchWorkspaceStore.swift`
- `Sources/Mica/Features/Workbench/WorkbenchProxyPresentation.swift`
- `Sources/Mica/Features/Workbench/WorkbenchProxyInteraction.swift`
- `Sources/Mica/Features/Workbench/WorkbenchProxies.swift`
- `Sources/Mica/Features/Workbench/WorkbenchProxyGroupPanels.swift`

## Ownership And Safety

Implementation workers receive disjoint file ownership and must not revert current user changes. Main session owns cross-layer state-machine integration, final validation and task status. No automated command may load a profile, connect to a controller, invoke remote actions or modify system networking.

## Rollback Points

1. Keep endpoint/publication tests while reverting only the channel lifecycle implementation if generation cleanup regresses.
2. Keep typed navigation and truthful unresolved states even if visual node scrolling must temporarily fall back to inspector-only reveal.
3. Revert any performance-only optimization that misses the two-run 10% retention threshold; correctness fixes remain.
