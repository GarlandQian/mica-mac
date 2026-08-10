# Workbench 剩余源码职责拆分实施计划

## Execution Rules

- 用户在本 PRD/design/implement 摘要之后再次明确批准，才运行 `task.py start` 并修改产品源码。
- 实现前完成 `trellis-before-dev`；全部代码和合同同步后使用 `trellis-check` 集中验证。
- 以当前 dirty worktree（包括已完成的 Proxies 拆分）为基线，只追加本任务差异，不回退或覆盖既有修改。
- 按完整声明块机械迁移；除 import、最小访问级别和 SwiftUI-only appearance extension 外不改实现。
- 不新增 package、业务测试框架、本地化文案或生产 mock；不启动应用、不访问控制器、不提交或推送。
- 临时输出只放 `tmp/codex/`，验证结束后移除本任务产生的 disposable artifacts。

## Phase 1. Baseline And Ownership Map

- [x] 记录 Workbench 文件清单、行数、顶层声明和现有 verifier 按文件读取方式。
- [x] 识别真正混合所有权的 shell/shared/data/management/personalization 文件，并明确保留不拆的内聚文件。
- [x] 确定每个新文件的声明边界、import 目标和最小跨文件访问策略。
- [x] 建立 PRD、technical design、验证计划和 dirty-worktree 限制。

## Phase 2. Shell And Shared Layers

- [x] 从 Chrome 迁移 window、sidebar、status/session/outcome 声明，保留 destination/root/lifecycle。
- [x] 将 design token 与 shared SwiftUI primitives 分离为 DesignSystem / VisualSystem。
- [x] 将 shared data 的 interaction、View primitives 和 pure presentation 分离。
- [x] 用 `rg` 检查每个新 owner 的声明唯一性、旧 owner 无残留和 import/access 边界。

## Phase 3. Data Pages

- [x] 拆出 Connections pulse projection/cache/cadence 与 pulse View，保持现有 root/projection/details 结构。
- [x] 拆出 Logs pure presentation/cache，保留 table/inspector View，并将 SwiftUI tint 留在 View 文件。
- [x] 拆出 Rules pure presentation 和 details，收敛 root table。
- [x] 拆出 Sources pure presentation 和 details，收敛 root table。
- [x] 检查跨页面共享 projection、selection、cache 和 helper 没有重复或遗漏。

## Phase 4. Management Pages

- [x] 从 Actions 拆出 Tailscale section 与 endpoint/peer Views。
- [x] 从 Controllers 拆出 delete/list/connection-test pure presentation。
- [x] 将 Diagnostics 分为 pure presentation、root 和 shared/detail components。
- [x] 保持 Configuration、Settings 与 Management shared definitions 不变。

## Phase 5. Overview Personalization

- [x] 从 OverviewPersonalization 拆出 persistence client/envelope/mutations/store。
- [x] 拆出 conflict/window coordinator/draft state。
- [x] 确认 layout model、持久化 key/编码和窗口 identity 没有语义变化。

## Phase 6. Contracts And Documentation

- [x] 更新 `workbench-ui-contract.md` 精确文件清单和 ownership 条款。
- [x] 更新 `expectedWorkbenchFiles` 与 family aggregates，并保留/新增 per-file 正反 ownership 断言。
- [x] 将 destination/sidebar/table/detail/projection/cache/persistence 断言定位到真实 owner，不删除原业务合同。
- [x] 同步 `docs/ARCHITECTURE.md` 中受影响的 Workbench 所有权描述。
- [x] 仅在现有测试明确依赖文件职责时做最小调整，不为纯拆分新增覆盖率测试。

## Phase 7. Consolidated Validation

完成全部相关修改后依次运行：

```bash
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
swift test --filter WorkbenchNavigationTests --scratch-path tmp/codex/swift-build
swift test --filter WorkbenchDataProjectionTests --scratch-path tmp/codex/swift-build
swift test --filter WorkbenchManagementProjectionTests --scratch-path tmp/codex/swift-build
swift test --filter WorkbenchOverviewPersonalizationTests --scratch-path tmp/codex/swift-build
swift test --filter WorkbenchOperationOutcomePresentationTests --scratch-path tmp/codex/swift-build
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
python3 ./.trellis/scripts/task.py validate 08-06-workbench-remaining-source-decomposition
```

- [x] 失败后只重跑受影响检查；涉及 shared projection/cache 的最终状态必须通过完整测试。
- [x] 运行 `trellis-check`，修复已确认的 spec/source/test drift。
- [x] 清理 `tmp/codex/swift-build` 和本任务产生的 disposable artifacts。
- [x] 记录验证结果；runtime smoke 与真实控制器访问按范围明确跳过。

### Validation Results (2026-08-06)

- `node --check scripts/verify-real-controller-source.mjs`：通过。
- `node scripts/verify-real-controller-source.mjs`：通过，49 个 Workbench Swift 文件与分层 ownership 合同一致。
- `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`：通过。
- 五组定向 Workbench tests：共 89 项通过（Navigation 12、Data Projection 36、Management Projection 15、Overview Personalization 22、Operation Outcome 4）。
- `swift build --scratch-path tmp/codex/swift-build`：通过。
- `swift test --scratch-path tmp/codex/swift-build`：27 个 suite、298 项测试全部通过。
- `git diff --check`：通过；Workbench debug/unsafe pattern scan 无匹配。
- `trellis-check`：完成，未发现未修复的 spec/source/test drift；纯重构无需新增行为测试。
- `python3 ./.trellis/scripts/task.py validate 08-06-workbench-remaining-source-decomposition`：通过（仅有既存合同文件超过 context injection 阈值的非阻塞提示）。
- 已移除 1.3 GB 的 `tmp/codex/swift-build` disposable artifacts。按任务范围未运行 runtime smoke、未启动 Mica、未访问真实控制器。

## Final Review Gate

- [x] 用户在本规划摘要后明确批准开始实现。
- [x] `task.py validate 08-06-workbench-remaining-source-decomposition` 通过。
- [x] 运行 `task.py start 08-06-workbench-remaining-source-decomposition` 后才修改产品源码。
