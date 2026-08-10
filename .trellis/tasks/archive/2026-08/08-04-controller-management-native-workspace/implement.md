# 控制器管理原生工作区重构实施计划

## Phase 0. Pre-development gate

- [x] 运行 `trellis-before-dev`，重新读取 active task、backend/controller-data、live-session 和 workbench UI 合同。
- [x] 检查 `git status --short`，记录并保护所有既有未提交修改；只修改本任务相关文件。
- [x] 确认当前 `WorkbenchManagement.swift` 类型边界、相关 tests、verifier 断言和 `WorkbenchSettings.swift` 现状。
- [x] 不创建分支、不启动 Mica、不访问控制器、不运行 runtime smoke。

## Phase 1. Mechanical file split

- [x] 将 Controllers projection/view/report ownership island 机械移动到 `WorkbenchControllers.swift`。
- [x] 将 Configuration ownership island 机械移动到 `WorkbenchConfiguration.swift`。
- [x] 将 Actions projection/view/backend-specific subviews 机械移动到 `WorkbenchActions.swift`。
- [x] 将 Diagnostics projection/visibility/layout/view ownership island 机械移动到 `WorkbenchDiagnostics.swift`。
- [x] 仅在 `WorkbenchManagement.swift` 保留真实共享原语；保持类型名、入口和最小访问级别。
- [x] 更新 `.trellis/spec/frontend/workbench-ui-contract.md` 的精确文件架构。
- [x] 更新 `scripts/verify-real-controller-source.mjs` 的 expected files、management aggregation、source-section 断言和本地化扫描。
- [x] 执行一次高风险边界检查：`swift build`。只修复拆分造成的编译/访问问题，暂不做 UI 改造。

**Rollback point:** 新文件和 verifier/spec 文件映射。Build 通过前不进入下一阶段。

## Phase 2. Controllers and RouterEditor

- [x] 把 Controllers 整理为稳定 master-detail：regular 宽度左右 split，compact 宽度上下 split。
- [x] 保持列表源顺序、过滤顺序和 workspace selection；列表整行可选择且无网络副作用。
- [x] 将 Use、Test、Edit、Delete、Move Previous/Next 集中到 detail 命令上下文。
- [x] 确保只有 Use 调用 `selectRouter`；活动 profile 不提供可执行 Use。
- [x] 保持 delete confirmation 的 controller ID/generation 失效规则；补齐同窗口行内反馈。
- [x] 重排 RouterEditor sections，移除重复标签和固定巨宽布局，保持同窗口 overlay、可见命令、校验、test state、discard state。
- [x] 保持 `upsertRouter(from:)` 和 `FileSecretStore` 事务不变。

**Focused checks:** 复用现有 controller ordering/selection/delete confirmation/editor presentation/profile transaction/FileSecretStore 测试。纯布局不新增测试。

## Phase 3. Configuration and Actions

- [x] 让 Configuration row 完全由报告字段与 capability projection 驱动；移除不支持占位和空 section。
- [x] 使用共享 form primitive 统一行布局、尾部控件、进行中状态和错误反馈。
- [x] 保持 `ControllerConfigMutation`、乐观更新、回滚和 generation 回收边界。
- [x] 将 Actions 渲染为紧凑原生列表/表单，只保留真实可执行 row 和原有顺序。
- [x] 为危险 operation 使用 inline `WorkbenchRuntimeConfirmation`，在确认时重新验证 controller ID、generation、operation ID 和 capability。
- [x] Session/目标变化时自动失效 pending confirmation；执行中防重复提交。

**Focused checks:** 复用现有 capability/action order/runtime confirmation/config generation 测试；只有 projection 或核心契约发生变化时才同步测试。

## Phase 4. Diagnostics

- [x] 重构顶部结论带，使状态、影响和建议可直接阅读，不显示 assignment string。
- [x] 统一一级/二级 disclosure 为整行 Button、统一动画和 Reduce Motion 行为。
- [x] 在 projection 层同时过滤两个层级的不支持 row 与空 section。
- [x] 将展开内容整理为用户可读字段；移除 API 路径、机器键值墙和 raw payload。
- [x] 保持 Copy Report 的安全技术信息与既有 redaction 边界。
- [x] 消除嵌套 lazy/scroll 容器、row body 全集格式化和持续全树动画；多 section 展开仍保持单一滚动所有者。

**Focused checks:** 复用并按需补充 diagnostics field projection、visibility、redaction 和 disclosure state 测试。视觉动画本身不新增脆弱 snapshot 测试。

## Phase 5. Cross-surface polish

- [x] 统一 Controllers、RouterEditor、Configuration、Actions、Diagnostics 的 page fill、separator、间距、字体、symbol 和 8pt 圆角上限。
- [x] 检查 standard/comfortable/large/extraLarge 下文字即时缩放且不改变 width mode。
- [x] 检查窄/中/宽布局的换行、detail 宽度、命令压缩和主滚动所有权。
- [x] 补齐英文、简体中文、help、tooltips 和 accessibility 文案。
- [x] 更新 `docs/` 或项目 skill 中受文件拆分影响的长期架构映射；不复制 Trellis task 细节。
- [x] 清理 `tmp/codex/` 中本任务不再需要的产物。

## Phase 6. Concentrated validation

按以下顺序集中验证；失败后只重跑受影响项：

1. `node --check scripts/verify-real-controller-source.mjs`
2. `node scripts/verify-real-controller-source.mjs`
3. `python3 -m json.tool Sources/Mica/Resources/Localizable.xcstrings`
4. `swift test --filter WorkbenchManagementProjectionTests`
5. `swift test --filter WorkbenchNavigationTests`
6. `swift test --filter FileSecretStoreTests`
7. 根据实际核心改动补跑相关 profile/config/runtime transaction 测试；若仅视图组合变化则不新增或扩张测试范围。
8. `swift build`
9. 因本任务修改共享 management primitives、profile/control flow 与 verifier 架构，最终运行一次 `swift test`。
10. `git diff --check`
11. `python3 ./.trellis/scripts/task.py validate 08-04-controller-management-native-workspace`

禁止运行 Mica、runtime smoke 或任何会访问真实控制器的命令。

## Phase 7. Review and handoff

- [x] 核对所有 acceptance criteria 与 diff，确认未修改无关页面或依赖。
- [x] 使用 `trellis-check` 完成任务级规格、数据流和安全边界复核。
- [x] 汇报机械拆分、页面结果、验证命令、未运行的 runtime 项和用户手工视觉验收清单。
- [x] 等待用户确认后再完成/归档任务；不自动提交 Git。
