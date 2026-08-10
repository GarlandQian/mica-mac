# Proxies 源码职责拆分实施计划

## Execution Rules

- 用户批准本方案后才运行 `task.py start` 并修改产品源码。
- 当前为 Codex inline 流程：开始实现前完成 `trellis-before-dev`；代码完成后运行 `trellis-check`。
- 以当前 dirty worktree 为基线，只追加 Proxies 拆分差异，不回退 Overview、verifier、UI contract 或其他用户修改。
- 先完成全部机械迁移和合同同步，再集中验证。
- 不改变 UI/数据/会话行为，不新增测试框架、package 或本地化文案。
- 临时构建输出只放 `tmp/codex/`，结束时清理；不启动应用、不访问控制器、不提交或推送。

## Phase 1. Baseline And Boundaries

- [x] 记录当前 Workbench 文件清单、Proxies 文件行数、顶层声明边界和相关 dirty 状态。
- [x] 证明旧私有 View 岛无外部引用，并与已归档“单一纵向策略组流替换目录 + Inspector”决策对照。
- [x] 追踪 `ProxyProjection`、`ProxyWorkspaceProjection`、scheduler/coordinator 在 Proxies、Connections、Rules、测试和 verifier 中的消费者。
- [x] 确定 root / panels / interaction / presentation 四文件所有权及最小访问级别变化。

## Phase 2. Mechanical Source Split

- [x] 将 interaction/update 声明机械迁移到 `WorkbenchProxyInteraction.swift`，保持 scheduler/coordinator 实现和 timing 常量不变。
- [x] 将 session/operation presentation、catalog/index/cache、workspace/projection 声明机械迁移到 `WorkbenchProxyPresentation.swift`。
- [x] 将 `WorkbenchProxies.swift` 收敛为 `WorkbenchPolicyGroupsView` 根组合，保留现有状态、回调、rebuild 和 AppModel intent。
- [x] 调整各文件 imports 和最小跨文件访问级别；将存活的 file-private 非空 helper 唯一命名为 `proxyNonBlank`。

回退点：移动按完整顶层声明块进行；若编译失败，只修复已确认的 import/access 边界，不改业务逻辑。

## Phase 3. Remove Superseded UI

- [x] 删除 `ProxyCompactGroupDirectoryHeader` 至 `ProxyNodeVerbatimDetailField` 的 12 个不可达私有 View。
- [x] 删除 `ProxyWorkspaceLayoutMode`、`ProxyMasterDetailMetrics` 和 `ProxyOpenPathRibbonProjection`。
- [x] 删除 `proxyMasterDetailWidthsStayWithinApprovedBounds`，保留当前纵向策略组与所有 active projection/scheduler 测试。
- [x] 用 `rg` 确认删除类型无残留声明或引用，当前根仍只组合 `ProxyPolicyGroupPanel`。

回退点：若发现任何非测试生产消费者，暂停删除并恢复该声明；不得创建 legacy compatibility 文件。

## Phase 4. Executable Contract Sync

- [x] 更新 `workbench-ui-contract.md` 精确文件清单和 Proxies ownership 说明。
- [x] 更新 `expectedWorkbenchFiles` 以及 `proxyRoot`/`proxyPanels`/`proxyInteraction`/`proxyPresentation` 聚合。
- [x] 将现有 verifier 断言定位到真实所有者，删除旧 master-detail/ribbon 类型断言。
- [x] 增加文件 ownership 正反断言，不弱化顺序、GLOBAL、缓存、metadata、capability 和 workspace 合同。
- [x] 更新 task scope 并运行 Trellis validation。

## Phase 5. Consolidated Validation

依次运行：

```bash
swift test --filter WorkbenchProxyWorkspaceTests --scratch-path tmp/codex/swift-build
swift test --filter WorkbenchTimelineAndProxyTests --scratch-path tmp/codex/swift-build
swift test --filter WorkbenchDataProjectionTests --scratch-path tmp/codex/swift-build
node --check scripts/verify-real-controller-source.mjs
node scripts/verify-real-controller-source.mjs
python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings >/dev/null
swift build --scratch-path tmp/codex/swift-build
swift test --scratch-path tmp/codex/swift-build
git diff --check
python3 ./.trellis/scripts/task.py validate 08-06-proxies-source-decomposition
```

- [x] 失败后只重跑受影响检查；最后一次共享 projection 变更必须通过完整测试。
- [x] 清理 `tmp/codex/swift-build` 和本任务产生的 disposable artifacts。
- [x] 运行 `trellis-check`，处理已验证的 spec/source/test 问题。
- [x] 执行 durable spec pass；除 Workbench 文件所有权外不扩展文档范围。

## Final Review Gate

- [x] 用户在本 PRD/design/implement 摘要之后明确批准开始实现。
- [x] `task.py validate 08-06-proxies-source-decomposition` 通过。
- [x] 运行 `task.py start 08-06-proxies-source-decomposition` 后才修改产品源码。

## Validation Results

- `WorkbenchProxyWorkspaceTests`: 16 tests passed.
- `WorkbenchTimelineAndProxyTests`: 27 tests passed after removing the superseded geometry-only test.
- `WorkbenchDataProjectionTests`: 36 tests passed.
- Full Swift Testing run: 298 tests in 27 suites passed; all XCTest suites passed.
- Swift build, source verifier, localization JSON, `git diff --check`, and Trellis task validation passed.
- Runtime smoke and real-controller access were intentionally skipped by task scope.
